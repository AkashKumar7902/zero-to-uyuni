#!/usr/bin/env bash
# Level 1 CHECK: a real blueprint (>= 20 PersistentVolumeClaims; catchup.sh 1 counts too). Tells the game (count only).
D=$(dirname "$0"); BP=${BLUEPRINT:-/root/uyuni.yaml}; CHECK=${CHECK_FILE:-/root/.check}
[ -e "$D/game.sh" ] || D=/root/osas26   # Killercoda may run a CHECK from another directory: the kit lives in /root/osas26 (UBR 5.1)
test -s "$BP" || { echo "Render the chart first (or /root/osas26/catchup.sh 1)" > "$CHECK"; exit 1; }
n=$(grep -c '^kind: PersistentVolumeClaim' "$BP" 2>/dev/null)
[ "${n:-0}" -ge 20 ] || { echo "Your blueprint looks unfinished (${n:-0} volumes). Render it again, or /root/osas26/catchup.sh 1" > "$CHECK"; exit 1; }
bash "$D/probe.sh" blueprint >/dev/null
"$D/achieve.sh" chart "Blueprint read: you know what HQ is made of."
