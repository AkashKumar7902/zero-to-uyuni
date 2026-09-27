#!/usr/bin/env bash
# outage.sh [roster] - Level 4 OUTAGE HP. Counts only, never names. Also posts each step to the game (fire-and-forget).
#   outage.sh roster   16:15:30, BEFORE "Go": remembers which crew nodes answer HQ now (the crew on this shift)
#   outage.sh          a check: OUTAGE HP = roster nodes that do not answer now. The room wins at
#                      down <= min(max(1, roster/10), roster - 1): it forgives expired or abandoned sandboxes (a room
#                      of 5 can win too), but always needs at least one node back (K1, 27 Sep: a roster of 1 or 2 no
#                      longer "wins" while every node is dark). The game uses exactly this rule and the same rounded
#                      HP: geeko-hq's tests/unit/game/outage-parity.test.mjs runs this script against it.
# LD-2: Uyuni's master sets timeout and gather_job_timeout to 120, so "salt test.ping -t 5" waits ~126 s as soon as one
# node is dark. The manage runner takes gather_job_timeout: ~12 s with a dark node, ~2 s without (measured, Salt 3006.9).
# Golden's one-shot timers run it at 16:15:30 (roster) and 16:18:30 · 16:20:30 · 16:22:30 (checks); d-roster and
# d-outage stay the manual fallbacks. Never run it in a loop.
set -uo pipefail
ADM=/etc/rancher/rke2/rke2.yaml; D=${BOARD_DIR:-/root/osas26}; R=$D/outage-roster; N=$D/outage-n
RX='^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$'
k(){ kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
if [ "${BOARD_FAKE:-}" = 1 ]; then k(){ cat "$D/${FAKE_STATUS:-fake-status.json}"; }; fi
GP=${GAME_POST:-/usr/local/sbin/osas26-game-post}
gp(){ [ -x "$GP" ] && ( timeout 5 "$GP" "$1" >/dev/null 2>&1 & ); return 0; }   # never blocks, never fails
ids_json(){ grep -E "$RX" | jq -R . | jq -sc .; }
status(){ k salt-run manage.status tgt='osas26-*' timeout=5 gather_job_timeout=5 --out=json 2>/dev/null \
          | jq -r '.up[]?' 2>/dev/null | grep -E "$RX" | sort; }
if [ "${1:-}" = roster ]; then
  status | grep . > "$R" || true
  echo 0 > "$N"; rm -f "$D/room-status"
  gp "{\"t\":\"roster\",\"ids\":$(ids_json < "$R")}"
  echo "roster: $(grep -c . "$R" || true) crew nodes on this shift"; exit 0; fi
[ -s "$R" ] || { echo "no roster yet: run 'outage.sh roster' before ./break.sh"; exit 1; }
n=$(( $(cat "$N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$N"
gp "{\"t\":\"check_start\",\"n\":$n}"          # the game's sonar runs while HQ asks (about 12 s)
up=$(status)
total=$(grep -c . "$R")
back=$(comm -12 "$R" <(printf '%s\n' "$up" | grep .))
down=$(( total - $(printf '%s\n' "$back" | grep -c .) ))
win=$(( total / 10 )); (( win < 1 )) && win=1; (( win > total - 1 )) && win=$(( total - 1 ))   # K1: at least one back
gp "{\"t\":\"check\",\"n\":$n,\"up\":$(printf '%s\n' "$back" | ids_json),\"roster\":$total,\"down\":$down}"
pct=$(( (200 * down + total) / (2 * total) )); bar=""   # rounded half up, as the game shows it
for ((i = 1; i <= 30; i++)); do if (( i * 100 <= pct * 30 )); then bar+="#"; else bar+="."; fi; done
printf '\n  OUTAGE HP [%s] %d%%   (%d of %d crew nodes still dark)\n\n' "$bar" "$pct" "$down" "$total"
if (( down <= win )); then
  printf '  ==================================================\n   O U T A G E   D E F E A T E D !   Mantap, crew!\n   The whole room brought HQ'"'"'s fleet back.\n  ==================================================\n\n'
  echo "OUTAGE DEFEATED by the whole crew" > "$D/room-status"
else
  echo "OUTAGE HP ${pct}%: runbook on the screen" > "$D/room-status"
fi
