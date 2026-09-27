#!/usr/bin/env bash
# lab/runner/heartbeat.sh MINUTES - RUNNER-HQ: keep the job (and so HQ) alive for MINUTES, one heartbeat line a minute
# to the job log and /root/osas26/runner/heartbeat.log: memory, load, disk, Uyuni pods, Salt keys, the relay's doors.
# Stops early, cleanly (the log upload still runs), when /root/osas26/runner/STOP exists:
#   ssh -p <SSH_PORT> root@bore.pub touch /root/osas26/runner/STOP
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib.sh"
MIN=${1:?minutes}; M=$W/runner; L=$M/heartbeat.log; install -d -m 0700 "$M"
end=$(( $(date +%s) + MIN * 60 ))
k(){ timeout 20 kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@" 2>/dev/null; }
echo "heartbeat: up to ${MIN} min, until $(date -u -d "@$end" +%T) UTC; early stop: touch $M/STOP" | tee -a "$L"
while [ "$(date +%s)" -lt "$end" ]; do
  [ -e "$M/STOP" ] && { echo "$(date -u +%T) STOP file found: ending the keep-alive" | tee -a "$L"; break; }
  mem=$(free -m | awk '/^Mem:/{printf "mem %d/%d MiB (avail %d)", $3, $2, $7}')
  load=$(cut -d' ' -f1-3 /proc/loadavg); disk=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
  pods=$(kubectl -n uyuni get pods --no-headers 2>/dev/null | awk '{printf "%s:%s ", $1, $2}' | sed 's/-[a-z0-9]*-[a-z0-9]*:/:/g')
  keys=$(k salt-key --out=json | jq -r '"keys acc \(.minions|length) pend \(.minions_pre|length)"' 2>/dev/null || echo "keys ?")
  doors=""; for d in salt-pub salt-req ssh; do doors+="$d=$(cut -d' ' -f1-2 /run/osas26-relay/$d.probe 2>/dev/null || echo -) "; done
  printf '%s | %s | load %s | / %sG free | %s| %s | %s\n' "$(date -u +%T)" "$mem" "$load" "$disk" "$pods" "$keys" "$doors" | tee -a "$L"
  sleep 60
done
