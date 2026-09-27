#!/usr/bin/env bash
# lab/runner/server-env.sh [OUT] - RUNNER-HQ: the attendee/server.env for THIS run (public, no secrets), from lab.env
# (HQ's own name), relay.env (the relay's address) and HQ's master key fingerprint. Default OUT: /root/osas26/server.env.
#   FQDN=uyuni.<runner's own address>.sslip.io   HQ's name (Uyuni's certificate and config use it; pods resolve it)
#   SERVER_IP=<the relay's IPv4>                 join.sh writes "SERVER_IP FQDN" into the sandbox's /etc/hosts
#   RELAY=<relay host>                           marks the relay mode for lab/lint-server-env.sh
# The Salt ports are not written: the relay serves exactly 4505/4506 (relay.sh, SALT_FIXED=1), which the kit expects.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib.sh"
lab_env
OUT=${1:-$W/server.env}
[ -s "$W/relay.env" ] || die "no relay.env: run relay.sh up salt first"
rv(){ sed -n "s/^$1=//p" "$W/relay.env"; }
[ "$(rv SALT_PUB_PORT)" = 4505 ] && [ "$(rv SALT_REQ_PORT)" = 4506 ] \
  || die "the relay's Salt ports are $(rv SALT_PUB_PORT)/$(rv SALT_REQ_PORT), not 4505/4506: the kit cannot use them (D-K2)"
fp=$(kubectl -n uyuni exec deploy/uyuni -c uyuni -- salt-key -F master 2>/dev/null | sed -n 's/^master\.pub: *//p' | tr -d '\r')
[ -n "$fp" ] || die "could not read HQ's master.pub fingerprint"
umask 022
cat > "$OUT" <<EOF
# server.env - where HQ and the game live. Public, no secrets. Written by lab/runner/server-env.sh on a GitHub runner
# at $(date -u +%FT%TZ): HQ runs on a runner and its Salt doors are $(rv RELAY_SERVER):4505/4506 (a public TCP relay).
FQDN=${FQDN}
SERVER_IP=$(rv RELAY_IP)
RELAY=$(rv RELAY_SERVER)
KEY=1-osas26-fleet
GAME_URL=${GAME_URL_FOR_ENV-https://geeko-hq.pages.dev}
HQ_MASTER_FINGER_TAIL=${fp: -5}
HQ_MASTER_FINGER=${fp}
EOF
STRICT=1 bash "$LAB/lint-server-env.sh" "$OUT" >&2
cat "$OUT"
