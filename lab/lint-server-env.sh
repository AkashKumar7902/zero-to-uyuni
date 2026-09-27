#!/usr/bin/env bash
# lint-server-env.sh [attendee/server.env] - FREE-GOLDEN §8.3 D-K5: the file every sandbox fetches must be consistent.
#   the FQDN's dashed IP equals SERVER_IP; KEY is the fleet key; GAME_URL is https or empty; HQ_MASTER_FINGER_TAIL
#   is empty or xx:yy. The documented example (A.B.C.D) passes with a notice; STRICT=1 (the push after the HQ build)
#   fails on it.
set -uo pipefail
f=${1:-attendee/server.env}; bad=0
v(){ sed -n "s/^$1=//p" "$f" | head -1; }
fq=$(v FQDN); ip=$(v SERVER_IP); key=$(v KEY); gu=$(v GAME_URL); tail=$(v HQ_MASTER_FINGER_TAIL)
if [ "$ip" = A.B.C.D ]; then
  echo "server.env: the documented EXAMPLE (HQ's address is not known yet)"
  [ "${STRICT:-0}" = 1 ] && { echo "STRICT: fill FQDN/SERVER_IP/HQ_MASTER_FINGER_TAIL from the new HQ (D-K1)"; bad=1; }
else
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "SERVER_IP '$ip' is not an IPv4 address"; bad=1; }
  [ "$fq" = "uyuni.${ip//./-}.sslip.io" ] || { echo "FQDN '$fq' does not match SERVER_IP $ip (want uyuni.${ip//./-}.sslip.io)"; bad=1; }
fi
[ "$key" = 1-osas26-fleet ] || { echo "KEY '$key' is not 1-osas26-fleet"; bad=1; }
[ -z "$gu" ] || [[ $gu =~ ^https://[a-z0-9.-]+$ ]] || { echo "GAME_URL '$gu' must be https://host (or empty = game off)"; bad=1; }
[ -z "$tail" ] || [[ $tail =~ ^[0-9a-f]{2}:[0-9a-f]{2}$ ]] || { echo "HQ_MASTER_FINGER_TAIL '$tail' must be xx:yy (or empty)"; bad=1; }
[ $bad = 0 ] && echo "server.env: consistent"
exit $bad
