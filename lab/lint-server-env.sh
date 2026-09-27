#!/usr/bin/env bash
# lint-server-env.sh [attendee/server.env] - FREE-GOLDEN §8.3 D-K5: the file every sandbox fetches must be consistent.
#   the FQDN's dashed IP equals SERVER_IP; KEY is the fleet key; GAME_URL is https or empty; HQ_MASTER_FINGER_TAIL
#   is empty or xx:yy. The documented example (A.B.C.D) passes with a notice; STRICT=1 (the push after the HQ build)
#   fails on it. RELAY=<host> (RUNNER-HQ, lab/runner/): SERVER_IP is the relay's IPv4 and the FQDN keeps the runner's
#   own (private) address, because join.sh maps the FQDN to SERVER_IP in /etc/hosts; the Salt ports stay 4505/4506.
#   RELAY=cloudflare-quick: SERVER_IP is 127.0.0.1 (the sandbox's own forwarders, cf-doors.sh) and CF_PUB_HOST and
#   CF_REQ_HOST are two different *.trycloudflare.com names.
#   MODE (v7) is empty (auto), solo or hq. STRICT=1 also wants MODE=solo, the room's pinned mode (PLAN R119: a copy
#   without it would send the whole room knocking on the relay); WANT_MODE=hq|auto names another intended mode.
set -uo pipefail
f=${1:-attendee/server.env}; bad=0
v(){ sed -n "s/^$1=//p" "$f" | head -1; }
fq=$(v FQDN); ip=$(v SERVER_IP); key=$(v KEY); gu=$(v GAME_URL); tail=$(v HQ_MASTER_FINGER_TAIL); relay=$(v RELAY)
mode=$(v MODE); hasmode=1; grep -q '^MODE=' "$f" || hasmode=0
if [ "$ip" = A.B.C.D ]; then
  echo "server.env: the documented EXAMPLE (HQ's address is not known yet)"
  [ "${STRICT:-0}" = 1 ] && { echo "STRICT: fill FQDN/SERVER_IP/HQ_MASTER_FINGER_TAIL from the new HQ (D-K1)"; bad=1; }
else
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "SERVER_IP '$ip' is not an IPv4 address"; bad=1; }
  if [ -n "$relay" ]; then
    [[ $relay =~ ^[a-z0-9.-]+$ ]] || { echo "RELAY '$relay' is not a host name"; bad=1; }
    [[ $fq =~ ^uyuni\.[0-9]{1,3}(-[0-9]{1,3}){3}\.sslip\.io$ ]] || { echo "FQDN '$fq' is not uyuni.<a-b-c-d>.sslip.io"; bad=1; }
    if [ "$relay" = cloudflare-quick ]; then
      cp=$(v CF_PUB_HOST); cr=$(v CF_REQ_HOST)
      [ "$ip" = 127.0.0.1 ] || { echo "RELAY=cloudflare-quick needs SERVER_IP=127.0.0.1 (the sandbox's forwarders), not $ip"; bad=1; }
      for h in "$cp" "$cr"; do [[ $h =~ ^[a-z0-9-]+\.trycloudflare\.com$ ]] || { echo "CF host '$h' is not a *.trycloudflare.com name"; bad=1; }; done
      [ "$cp" != "$cr" ] || { echo "CF_PUB_HOST and CF_REQ_HOST must differ"; bad=1; }
    fi
    echo "server.env: RELAY mode ($relay at $ip, HQ's own name $fq)"
  else
    [ "$fq" = "uyuni.${ip//./-}.sslip.io" ] || { echo "FQDN '$fq' does not match SERVER_IP $ip (want uyuni.${ip//./-}.sslip.io)"; bad=1; }
  fi
fi
[ "$key" = 1-osas26-fleet ] || { echo "KEY '$key' is not 1-osas26-fleet"; bad=1; }
[ -z "$gu" ] || [[ $gu =~ ^https://[a-z0-9.-]+$ ]] || { echo "GAME_URL '$gu' must be https://host (or empty = game off)"; bad=1; }
[ -z "$tail" ] || [[ $tail =~ ^[0-9a-f]{2}:[0-9a-f]{2}$ ]] || { echo "HQ_MASTER_FINGER_TAIL '$tail' must be xx:yy (or empty)"; bad=1; }
case "$mode" in ""|solo|hq) ;; *) echo "MODE '$mode' must be solo, hq or empty (auto)"; bad=1 ;; esac
if [ "${STRICT:-0}" = 1 ]; then
  want=${WANT_MODE:-solo}; [ "$want" = auto ] && want=""
  [ $hasmode = 1 ] && [ "$mode" = "$want" ] || { echo "STRICT: MODE is '$([ $hasmode = 1 ] && echo "$mode" || echo "<no MODE line>")', want '${want:-<empty: auto>}' (the room runs its own HQ: MODE=solo, R119)"; bad=1; }
fi
[ $bad = 0 ] && echo "server.env: consistent (MODE=${mode:-auto})"
exit $bad
