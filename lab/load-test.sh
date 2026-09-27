#!/usr/bin/env bash
# load-test.sh N PREFIX [HOLD_MIN] [STORM_AT_MIN] - PLAN §5.10 + FREE-GOLDEN G-LT60: N synthetic attendee sandboxes as
# containers on THIS machine (a GitHub runner via .github/workflows/load-test.yml, or any Linux box with docker or
# podman; never HQ itself). Each container is a stand-in for the Killercoda "ubuntu" image: attendee/ + preinstall.sh
# (lab/loadtest/Containerfile), then `join.sh <PREFIX><i>` on the non-systemd branch (its own machine-id).
# Before: on HQ, `osas26-salt-window open 50` and an accept loop with CAP >= all joins, e.g.
#   systemd-run --unit=osas26-accept-lt -p RuntimeMaxSec=40min -E CAP=70 /usr/local/sbin/osas26-accept-loop 30
# STORM_AT_MIN: at that minute every minion is killed, and restarted 90 s later (the Level 4 outage storm).
# Measure on HQ: start -> accepted (the loop's log), -> registered (board.sh), the promotion highstate, outage.sh.
# Every container is removed at the end, also on Ctrl-C.
# Env: CT=docker|podman (default: docker if present). LT_SERVER_ENV=/path/server.env mounts that file over the image's
#      copy (a server.env not pushed yet); SERVER_ENV_URL (default: the local copy, file:///root/osas26/server.env).
set -euo pipefail
N=${1:?usage: load-test.sh N PREFIX [HOLD_MIN] [STORM_AT_MIN]}; PFX=${2:?prefix, e.g. la}; HOLD=${3:-30}; STORM=${4:-}
[[ $PFX =~ ^[a-z]{1,4}$ ]] && [[ $N =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le 99 ] || { echo "N 1-99, PREFIX a-z (1-4)"; exit 2; }
CT=${CT:-$(command -v docker || command -v podman)} || true; [ -n "$CT" ] || { echo "needs docker or podman"; exit 2; }
MNT=(); [ -n "${LT_SERVER_ENV:-}" ] && MNT=(-v "$(readlink -f "$LT_SERVER_ENV"):/root/osas26/server.env:ro")
R=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd); IMG=osas26-lt:latest
ENVURL=${SERVER_ENV_URL:-file:///root/osas26/server.env}
names=(); for i in $(seq -w 1 "$N"); do names+=("osas26-lt-$PFX$i"); done
cleanup(){ echo "$(date -u +%T) removing ${#names[@]} containers"; "$CT" rm -f "${names[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
echo "$(date -u +%T) building $IMG from $R (attendee/ + preinstall.sh)"
"$CT" build -q -t "$IMG" -f "$R/lab/loadtest/Containerfile" "$R" >/dev/null
t0=$(date +%s)
for n in "${names[@]}"; do
  nick=${n#osas26-lt-}
  "$CT" run -d --name "$n" --hostname "$n" -e SERVER_ENV_URL="$ENVURL" "${MNT[@]}" "$IMG" \
    bash -c "/root/osas26/join.sh $nick > /root/join.log 2>&1; sleep infinity" >/dev/null
  sleep 1
done
echo "$(date -u +%T) started $N joins in $(( $(date +%s) - t0 )) s"
sleep 20
for n in "${names[@]}"; do printf '%s  %s\n' "$n" "$("$CT" exec "$n" sh -c 'cat /etc/osas26-id 2>/dev/null; grep -o "port 4506 [a-zA-Z ]*" /root/join.log | head -1' | tr '\n' ' ')"; done
end=$(( t0 + HOLD * 60 ))
if [ -n "$STORM" ]; then
  sleep $(( t0 + STORM * 60 - $(date +%s) > 0 ? t0 + STORM * 60 - $(date +%s) : 0 ))
  echo "$(date -u +%T) STORM: every minion down"; for n in "${names[@]}"; do "$CT" exec "$n" pkill -f venv-salt-minion || true; done
  sleep 90
  echo "$(date -u +%T) STORM over: every minion back"; for n in "${names[@]}"; do "$CT" exec "$n" venv-salt-minion -d || true; done
fi
while [ "$(date +%s)" -lt "$end" ]; do
  up=0; for n in "${names[@]}"; do "$CT" exec "$n" pgrep -f venv-salt-minion >/dev/null 2>&1 && up=$((up + 1)); done
  motd=0; for n in "${names[@]}"; do "$CT" exec "$n" grep -q 'GEEKO CORP' /etc/motd 2>/dev/null && motd=$((motd + 1)); done
  echo "$(date -u +%T) minions running $up/$N · crew cards $motd/$N"; sleep 60
done
