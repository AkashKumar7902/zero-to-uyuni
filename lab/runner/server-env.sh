#!/usr/bin/env bash
# lab/runner/server-env.sh [OUT] - RUNNER-HQ: the attendee/server.env for THIS run (public, no secrets), from lab.env
# (HQ's own name), relay.env (the relay's address) and HQ's master key fingerprint. Default OUT: /root/osas26/server.env.
#   FQDN=uyuni.<runner's own address>.sslip.io   HQ's name (Uyuni's certificate and config use it; pods resolve it)
#   SERVER_IP=<the relay's IPv4>                 join.sh writes "SERVER_IP FQDN" into the sandbox's /etc/hosts
#   RELAY=<relay host>                           marks the relay mode for lab/lint-server-env.sh
#   MODE=solo                                    v7: every sandbox runs its own HQ; only join.sh --hq (the HQ table)
#                                                uses this HQ. MODE_FOR_ENV=hq|auto writes another mode (auto = empty)
# The Salt ports are not written: the relay serves exactly 4505/4506 (relay.sh, SALT_FIXED=1), which the kit expects.
# SALT_RELAY=cloudflare-quick (relay.conf; relay-cf.sh): SERVER_IP=127.0.0.1, because every sandbox reaches HQ through
# its own local forwarders on 127.0.0.1:4505/4506 (cf-doors.sh, kit change D-K3), and CF_PUB_HOST/CF_REQ_HOST name
# the two quick tunnels.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib.sh"
lab_env
OUT=${1:-$W/server.env}
# shellcheck source=/dev/null
[ -r /etc/osas26/relay.conf ] && . /etc/osas26/relay.conf
SALT_RELAY=${SALT_RELAY:-bore}
rv(){ sed -n "s/^$1=//p" "$W/relay.env"; }
cv(){ sed -n "s/^$1=//p" "$W/cf.env"; }
if [ "$SALT_RELAY" = cloudflare-quick ]; then
  [ -s "$W/cf.env" ] && [ -n "$(cv CF_PUB_HOST)" ] && [ -n "$(cv CF_REQ_HOST)" ] || die "no cf.env with both Salt doors: run relay-cf.sh up salt first"
  sip=127.0.0.1; relay=cloudflare-quick; how="Cloudflare quick tunnels $(cv CF_PUB_HOST) (4505) and $(cv CF_REQ_HOST) (4506), reached through the sandbox's own forwarders (cf-doors.sh)"
  extra="CF_PUB_HOST=$(cv CF_PUB_HOST)
CF_REQ_HOST=$(cv CF_REQ_HOST)"
else
  [ -s "$W/relay.env" ] || die "no relay.env: run relay.sh up salt first"
  [ "$(rv SALT_PUB_PORT)" = 4505 ] && [ "$(rv SALT_REQ_PORT)" = 4506 ] \
    || die "the relay's Salt ports are $(rv SALT_PUB_PORT)/$(rv SALT_REQ_PORT), not 4505/4506: the kit cannot use them (D-K2)"
  sip=$(rv RELAY_IP); relay=$(rv RELAY_SERVER); how="$(rv RELAY_SERVER):4505/4506 (a public TCP relay)"; extra=""
fi
fp=$(kubectl -n uyuni exec deploy/uyuni -c uyuni -- salt-key -F master 2>/dev/null | sed -n 's/^master\.pub: *//p' | tr -d '\r')
[ -n "$fp" ] || die "could not read HQ's master.pub fingerprint"
mode=${MODE_FOR_ENV-solo}; [ "$mode" = auto ] && mode=""
case "$mode" in ""|solo|hq) ;; *) die "MODE_FOR_ENV '$mode' is not solo, hq or auto" ;; esac
umask 022
cat > "$OUT" <<EOF
# server.env - where HQ and the game live. Public, no secrets. Written by lab/runner/server-env.sh on a GitHub runner
# at $(date -u +%FT%TZ): HQ runs on a runner and its Salt doors are ${how}.
FQDN=${FQDN}
SERVER_IP=${sip}
RELAY=${relay}
KEY=1-osas26-fleet
GAME_URL=${GAME_URL_FOR_ENV-https://geeko-hq.pages.dev}
HQ_MASTER_FINGER_TAIL=${fp: -5}
HQ_MASTER_FINGER=${fp}
MODE=${mode}
EOF
[ -n "$extra" ] && printf '%s\n' "$extra" >> "$OUT"
WANT_MODE=${mode:-auto} STRICT=1 bash "$LAB/lint-server-env.sh" "$OUT" >&2
cat "$OUT"
