#!/usr/bin/env bash
# lab/runner/e2e.sh - RUNNER-HQ acceptance helpers, run ON HQ as root (over the relay's SSH). Read-only toward the
# sandboxes except what the lab itself does (the crew-card highstate, one remote command). Never prints a secret.
#   e2e.sh accept MIN [CAP]       the attendee accept loop as a transient unit (= go-accept); log: /root/osas26/accept-*.log
#   e2e.sh systems                registered osas26-* systems (API system.listSystems): id name
#   e2e.sh wait-reg N [TIMEOUT]   wait until >= N osas26-* systems are registered; prints the seconds it took
#   e2e.sh highstate              API system.scheduleApplyHighstate on every osas26-* system (the UI's Apply Highstate), waits
#   e2e.sh remote CMD             API system.scheduleScriptRun as root on every osas26-* system (the UI's Remote Command), waits
#   e2e.sh ping [TIMEOUT]         salt test.ping to osas26-*: "answered/accepted" and the seconds it took
#   e2e.sh pubport                the publish port the master advertises at auth, and the peers of Salt's two doors
#   e2e.sh reset                  delete every osas26-* system and key (between tests; never during a show)
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib.sh"
lab_env
RX='^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$'
k(){ kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
J=$(mktemp); C=$(mktemp); trap 'rm -f "$J" "$C"' EXIT; chmod 600 "$J" "$C"
API=https://$FQDN/rhn/manager/api
login(){ ( . "$W/secrets.env"; jq -nc --arg p "$ADMIN_PASS" '{login:"admin",password:$p}' ) \
           | curl -sk -c "$C" -H 'Content-Type: application/json' --data-binary @- "$API/auth/login" | jq -e .success >/dev/null \
         || die "API login failed"; }
get(){ curl -sk -b "$C" "$API/$1"; }
post(){ curl -sk -b "$C" -H 'Content-Type: application/json' --data-binary "$2" "$API/$1"; }
sids(){ get system/listSystems | jq -r '.result[] | "\(.id) \(.name)"' | awk -v rx="$RX" '$2 ~ rx'; }
wait_action(){   # wait_action AID N TIMEOUT -> "completed C failed F in S s"
  local aid=$1 n=$2 to=${3:-300} t0; t0=$(date +%s)
  while :; do
    c=$(get "schedule/listCompletedSystems?actionId=$aid" | jq '.result | length'); f=$(get "schedule/listFailedSystems?actionId=$aid" | jq '.result | length')
    [ $((c + f)) -ge "$n" ] && break; [ $(( $(date +%s) - t0 )) -ge "$to" ] && break; sleep 2; done
  echo "action $aid: completed $c, failed $f of $n in $(( $(date +%s) - t0 )) s"; }
case ${1:-} in
  accept)
    ts=$(date -u +%H%M%S)
    systemctl stop osas26-accept.service osas26-accept-manual.service 2>/dev/null
    systemd-run --unit=osas26-accept-manual -p RuntimeMaxSec=$(( ${2:?minutes} + 5 ))min -p StandardOutput="file:$W/accept-$ts.log" \
      -E CAP="${3:-60}" /usr/local/sbin/osas26-accept-loop "$2"
    echo "accept loop: ${2} min, CAP ${3:-60}, log $W/accept-$ts.log" ;;
  systems) login; sids ;;
  wait-reg)
    login; t0=$(date +%s); to=${3:-600}
    until [ "$(sids | grep -c .)" -ge "${2:?N}" ]; do [ $(( $(date +%s) - t0 )) -ge "$to" ] && { echo "TIMEOUT: $(sids | grep -c .) of $2 registered after $to s"; exit 1; }; sleep 5; done
    echo "registered $(sids | grep -c .) (wanted $2) after $(( $(date +%s) - t0 )) s" ;;
  highstate)
    login; mapfile -t ids < <(sids | awk '{print $1}'); [ ${#ids[@]} -gt 0 ] || die "no osas26 systems"
    aid=$(post system/scheduleApplyHighstate "$(jq -nc --argjson s "$(printf '%s\n' "${ids[@]}" | jq -sc .)" --arg d "$(date -u +%FT%TZ)" '{sids:$s,earliestOccurrence:$d,test:false}')" | jq -r .result)
    [[ $aid =~ ^[0-9]+$ ]] || die "scheduleApplyHighstate did not return an action id"
    wait_action "$aid" "${#ids[@]}" 300 ;;
  remote)
    login; mapfile -t ids < <(sids | awk '{print $1}'); [ ${#ids[@]} -gt 0 ] || die "no osas26 systems"
    body=$(jq -nc --argjson s "$(printf '%s\n' "${ids[@]}" | jq -sc .)" --arg sc "#!/bin/sh
${2:?command}" --arg d "$(date -u +%FT%TZ)" '{sids:$s,username:"root",groupname:"root",timeout:120,script:$sc,earliestOccurrence:$d}')
    aid=$(post system/scheduleScriptRun "$body" | jq -r .result)
    [[ $aid =~ ^[0-9]+$ ]] || die "scheduleScriptRun did not return an action id"
    wait_action "$aid" "${#ids[@]}" 300
    get "system/getScriptResults?actionId=$aid" | jq -r '.result[] | "  sid \(.serverId) rc \(.returnCode): \(.output | split("\n") | map(select(length>0)) | .[0] // "")"' ;;
  ping)
    t0=$(date +%s); acc=$(k salt-key --out=json | jq -r '.minions[]' | grep -cE "$RX")
    ans=$(k salt 'osas26-*' test.ping -t "${2:-15}" --out=json --static 2>/dev/null | jq '[to_entries[] | select(.value == true)] | length')
    echo "test.ping: ${ans:-0}/${acc} answered in $(( $(date +%s) - t0 )) s" ;;
  pubport)
    k python3 -c 'import salt.config as c; o=c.master_config("/etc/salt/master"); print("master publish_port", o["publish_port"], "ret_port", o["ret_port"], "salt", __import__("salt.version").version.__version__)'
    echo "Salt's established peers (inside the pod, via Traefik):"; k sh -c 'ss -Htn state established "( sport = :4505 or sport = :4506 )" | wc -l' ;;
  reset)
    login
    for s in $(sids | awk '{print $1}'); do post system/deleteSystem "{\"sid\":$s,\"cleanupType\":\"FORCE_DELETE\"}" >/dev/null; done
    for id in $(k salt-key --out=json | jq -r '.minions[], .minions_pre[], .minions_rejected[]' | grep '^osas26-'); do k salt-key -y -d "$id" >/dev/null; done
    echo "reset: $(sids | grep -c .) osas26 systems left" ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
