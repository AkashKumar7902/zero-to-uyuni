#!/usr/bin/env bash
# lab/runner/doors.sh env|state STATE|summary|publish-loop - RUNNER-HQ v7: the ONE public record of HQ's doors
# (doors.env), for the presenter's Mac (mac/door.sh) and the job summary. Run as root on HQ.
# Nothing here is secret: tunnel names, relay ports, the SSH host PUBLIC key, HQ's state, the node's private address.
# It is read from the live files every time, so a restarted door (a new Cloudflare name, a bore.pub port that fell
# back) shows up at once:
#   /run/osas26-cf/cf-ssh.host      the Cloudflare quick tunnel to sshd (relay-cf.sh; a restart = a NEW name)
#   /run/osas26-relay/*.port        bore.pub's ports (relay.sh; sticky; the SSH door may fall back to any port)
#   /root/osas26/lab.env            HQ's FQDN (once 00-os-prep.sh ran)
#   /root/osas26/runner/state       starting | building | up | failed | stopping (hq.yml writes it)
#   /root/osas26/runner/run-id      the GitHub run id (hq.yml writes it)
#   /etc/osas26/cap                 the HQ table's CAP (hq-table.sh writes it)
#   /root/osas26/leaps.state        leap-a / leap-b (leaps.sh writes it)
#   doors.sh env        print doors.env (lab/runner/doors-publish.mjs uploads it as a NEW artifact "doors-N" whenever
#                       it changes; mac/door.sh downloads the newest with gh)
#   doors.sh state S    record HQ's state
#   doors.sh summary    a Markdown block for $GITHUB_STEP_SUMMARY
set -uo pipefail
W=/root/osas26; CF=/run/osas26-cf; BR=/run/osas26-relay
rd(){ head -1 "$1" 2>/dev/null | tr -cd 'A-Za-z0-9._:/+=@ -'; }
kv(){ sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | tr -cd 'A-Za-z0-9._:/+=@ -'; }
node_ip(){ local ip; ip=$(kv /etc/osas26/relay.conf NODE_IP); [ -n "$ip" ] && { echo "$ip"; return; }
  ip -o -4 route get 1.1.1.1 | sed -n 's/.* src \([^ ]*\).*/\1/p'; }
fqdn(){ local f; f=$(kv "$W/lab.env" FQDN); echo "$f"; }
envout(){
  local cfh bp sp sq hk hkfp st rs
  cfh=$(rd "$CF/cf-ssh.host"); bp=$(rd "$BR/ssh.port"); sp=$(rd "$BR/salt-pub.port"); sq=$(rd "$BR/salt-req.port")
  rs=$(kv /etc/osas26/relay.conf RELAY_SERVER); rs=${rs:-bore.pub}
  hk=$(awk '{print $1" "$2}' /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null)
  hkfp=$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null | awk '{print $2}')
  st=$(rd "$W/runner/state"); st=${st:-starting}
  cat <<EOF
# doors.env - RUNNER-HQ's doors (public: names, ports, the SSH host PUBLIC key; never a secret). lab/runner/doors.sh
RUN_ID=$(rd "$W/runner/run-id")
HQ_STATE=${st}
CF_SSH_HOST=${cfh}
BORE_SERVER=${rs}
BORE_SSH_PORT=${bp}
SALT_DOORS=$( [ -n "$sp" ] && [ -n "$sq" ] && echo "$rs:$sp,$rs:$sq")
SSH_HOSTKEY=${hkfp}
SSH_HOSTKEY_PUB=${hk}
NODE_IP=$(node_ip)
FQDN=$(fqdn)
UI_LOCAL_PORT=18443
CAP=$(rd /etc/osas26/cap)
LEAPS=$(rd "$W/leaps.state")
CF_NAMES_SEEN=$(grep -c 'cf-ssh: \(UP\|NAME CHANGED\)' "$CF/events.log" 2>/dev/null || true)
EOF
}
case ${1:-} in
  env) envout ;;
  state) install -d -m 0700 "$W/runner"
         case ${2:-} in starting|building|up|failed|stopping) echo "$2" > "$W/runner/state" ;;
           *) echo "state: starting|building|up|failed|stopping" >&2; exit 2 ;; esac ;;
  summary)
    e=$(envout); g(){ sed -n "s/^$1=//p" <<<"$e"; }
    echo "### RUNNER-HQ doors (state: $(g HQ_STATE); key-only SSH, the osas26 key)"
    echo '```'
    [ -n "$(g CF_SSH_HOST)" ] && echo "Cloudflare: ssh -o ProxyCommand='cloudflared access ssh --hostname %h' root@$(g CF_SSH_HOST)"
    [ -n "$(g BORE_SSH_PORT)" ] && echo "bore.pub:   ssh -p $(g BORE_SSH_PORT) root@$(g BORE_SERVER)"
    [ -n "$(g SALT_DOORS)" ] && echo "HQ table:   Salt doors $(g SALT_DOORS) (CAP $(g CAP))"
    echo "host key:   $(g SSH_HOSTKEY)"
    echo "Mac:        ~/osas26-kit/door/door.sh status   (the newest 'doors-N' artifact; a new one whenever a door changes)"
    echo '```' ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
