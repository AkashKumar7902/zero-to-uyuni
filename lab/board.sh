#!/usr/bin/env bash
# board.sh - Geeko Corp fleet board (Mystery skin of research-v3 board-v3.sh). Projected "board" window: watch -n5 -t this.
# READ-ONLY toward Uyuni/Salt: salt-key --out=json, spacecmd group_listsystems (cached 30 s), local files only
# (ach.log from the listener, evidence-count from evidence.sh, room-status from outage.sh), systemctl is-active ("doors").
# Names ALPHABETICAL, never by score. The SHIFT XP bar was pre-cut in the v3 review (BOARD_XP=1 would show it; needs the listener).
# Counts only for evidence and the outage.
set -uo pipefail
ADM=/etc/rancher/rke2/rke2.yaml; D=${BOARD_DIR:-/root/osas26}; C=$D/.registered; L=$D/ach.log
k(){ kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
if [ "${BOARD_FAKE:-}" = 1 ]; then
  k(){ cat "$D/fake-keys.json"; }; DOORS=${BOARD_DOORS:-OPEN}                   # rehearsal replay / RED mode
else
  if systemctl is-active --quiet osas26-accept.service || systemctl is-active --quiet osas26-accept-manual.service
  then DOORS=OPEN; else DOORS=CLOSED; fi
  if [ ! -s "$C" ] || [ $(( $(date +%s) - $(stat -c %Y "$C") )) -ge 30 ]; then
    ( . $D/secrets.env
      k spacecmd -y -u admin -p "$ADMIN_PASS" -- group_listsystems osas26-fleet 2>/dev/null \
        | { grep -c '^osas26-' || true; } > "$C.tmp" && mv "$C.tmp" "$C" ) || true
  fi
fi
touch "$L"
ev=$(cat "$D/evidence-count" 2>/dev/null || echo sealed); st=$(cat "$D/room-status" 2>/dev/null || true)
k salt-key --out=json 2>/dev/null | jq -r '.minions[]' | grep -E '^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$' | sort \
| awk -v r="$(cat "$C" 2>/dev/null || echo '?')" -v L="$L" -v doors="$DOORS" -v ev="$ev" -v st="$st" -v showxp="${BOARD_XP:-0}" \
      -v tag="${BOARD_FAKE:+[REHEARSAL REPLAY - not live]}" '
  BEGIN { while ((getline line < L) > 0) { split(line, f, " "); a[f[2] " " f[3]] = 1 }
          n = split("chart join motd doctor", A, " ") }        # blueprint, onboarded, orders, incident
  { id[NR] = $0 }
  END {
    xp = 0
    for (i = 1; i <= NR; i++) { for (j = 1; j <= n; j++) if (A[j] == "join" || (id[i] " " A[j]) in a) xp++
                                split(id[i], p, "-"); cell[i] = p[2] }
    max = NR * n; pct = (max ? int(100 * xp / max) : 0); bar = ""
    for (b = 0; b < 40; b++) bar = bar (b < pct * 40 / 100 ? "#" : "-")
    if (tag != "") print tag
    printf "GEEKO CORP FLEET BOARD   doors: %-6s   crew on shift: %d (registered %s)\n", doors, NR, r
    if (showxp == 1) printf "SHIFT XP [%s] %d%%  (whole room)\n", bar, pct
    printf "final case evidence: %s%s\n\n", ev, (ev ~ /^[0-9]+$/ ? " crew nodes sealed it (count only)" : "")
    for (i = 1; i <= NR; i++) printf "%-19s%s", cell[i], (i % 4 == 0 ? "\n" : "")
    if (NR % 4) print ""
    if (st != "") printf "\n%s\n", st
  }'
