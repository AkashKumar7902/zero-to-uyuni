#!/usr/bin/env bash
# evidence.sh - how many crew nodes carry sealed final-case evidence (claim.sh wrote /root/.osas26-evidence)?
# Counts only on the board, never names. Golden's one-shot timer runs it at 16:25:30, BEFORE sandboxes expire
# (d-evidence stays the manual fallback). Writes $D/evidence-count for board.sh and credits.sh, and tells the game
# which machines answered "yes" (the game unions it with the seals it already knows; nothing is shown per crew).
# LD-2: publish with --async and read the job back after EVIDENCE_WAIT s (bounded), because Uyuni's master waits up to
# 120 s for silent minions on a synchronous call.
set -uo pipefail
D=${BOARD_DIR:-/root/osas26}; ADM=/etc/rancher/rke2/rke2.yaml
RX='^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$'
k(){ kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
if [ "${BOARD_FAKE:-}" = 1 ]; then
  k(){ case "$*" in *--async*) echo "Executed command with job ID: 20261003092530123456" ;; *) cat "$D/fake-evidence.json" ;; esac; }
fi
GP=${GAME_POST:-/usr/local/sbin/osas26-game-post}
gp(){ [ -x "$GP" ] && ( timeout 5 "$GP" "$1" >/dev/null 2>&1 & ); return 0; }
jid=$(k salt 'osas26-*' file.file_exists /root/.osas26-evidence --async 2>/dev/null | sed -nE 's/.*job ID: ([0-9]{20}).*/\1/p')
[ -n "$jid" ] || { echo "evidence: HQ did not start the job. Try d-evidence again once."; exit 1; }
sleep "${EVIDENCE_WAIT:-10}"
out=$(k salt-run jobs.lookup_jid "$jid" --out=json 2>/dev/null)
yes=$(jq -r 'to_entries[] | select(.value == true) | .key' <<<"$out" 2>/dev/null | grep -E "$RX")
ans=$(jq -r 'keys[]' <<<"$out" 2>/dev/null | grep -cE "$RX" || true)
n=$(printf '%s\n' "$yes" | grep -c . || true)
echo "${n:-0}" > "$D/evidence-count"
gp "{\"t\":\"evidence_hq\",\"ids\":$(printf '%s\n' "$yes" | grep . | jq -R . | jq -sc .),\"answered\":${ans:-0}}"
printf 'EVIDENCE SEALED: %d of the %d crew nodes that answered\n' "${n:-0}" "${ans:-0}"
