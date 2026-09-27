#!/usr/bin/env bash
# 50-content.sh (cp6) - PLAN §5.9. Run it OFF the projector: groups, the crew-card state channel, the two activation
# keys (no channels), the bootstrap script. Every spacecmd command exists in the 2026.08 source [L19]. Each create is
# skipped when the object exists, so a re-run after a fix is safe; the crew card is re-uploaded every time.
# KEY_LIMIT: the fleet key's usage limit = CAP (60, or 80 after the load test: PLAN §4.4).
set -euo pipefail; set +x
. "$(dirname "$(readlink -f "$0")")/lib.sh"
lab_env; cd "$W"; . ./secrets.env
t content_start
kx(){ kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }       # no stdin attached: nothing can block on a prompt
kxi(){ kubectl -n uyuni exec -i deploy/uyuni -c uyuni -- "$@"; }   # stdin only where a file is piped in
sc(){ kx spacecmd -y -u admin -p "$ADMIN_PASS" -- "$@"; }        # global -y answers confirmations [R5]; never on the projector [BOOT §2.7]
has(){ sc "$1" 2>/dev/null | tr '\r' '\n' | grep -qx -- "$2"; }    # has <list-command> <exact name>
has group_list osas26-fleet || sc group_create osas26-fleet "oSAS26 attendee sandboxes"
has group_list osas26-demo  || sc group_create osas26-demo  "oSAS26 Leap 16 demo VMs"
has configchannel_list osas26-welcome || sc configchannel_create -n osas26-welcome -l osas26-welcome -d "oSAS26 welcome state" -t state
kxi sh -c 'cat > /tmp/welcome.sls' < "$LAB/states/welcome.sls"      # the crew card (kit golden/crew-card.sls)
sc configchannel_updateinitsls -c osas26-welcome -f /tmp/welcome.sls -y
has activationkey_list 1-osas26-fleet || sc activationkey_create -n osas26-fleet -d "oSAS26 sandboxes (no channels)"   # -> 1-osas26-fleet, base "" [L19]
sc activationkey_setusagelimit 1-osas26-fleet "${KEY_LIMIT:-60}"
sc activationkey_addgroups 1-osas26-fleet osas26-fleet
sc activationkey_addconfigchannels -t 1-osas26-fleet osas26-welcome                # -t: never the interactive top/bottom prompt [R5]
sc activationkey_enableconfigdeployment 1-osas26-fleet
has activationkey_list 1-osas26-demo || sc activationkey_create -n osas26-demo -d "oSAS26 Leap 16 demo VMs"
sc activationkey_addgroups 1-osas26-demo osas26-demo
t content_keys
kx mgr-bootstrap --activation-keys=1-osas26-demo --script=bootstrap-osas26.sh --force-bundle   # the chart creates no default script [BOOT §7 Q1]
code=$(curl -sk -o /dev/null -w '%{http_code}' "https://${FQDN}/pub/bootstrap/bootstrap-osas26.sh"); echo "bootstrap script $code"
[ "$code" = 200 ] || die "bootstrap script not served"
t content_done
# read-back (no secrets): what HQ now holds
echo "--- groups";          sc group_list
echo "--- config channels"; sc configchannel_list
echo "--- keys";            sc activationkey_list
echo "--- 1-osas26-fleet";  sc activationkey_details 1-osas26-fleet
# P1 only - the client-tools channel for the extension package demo (23 pkgs / 65 MB) [BOOT §3.3 Option 1].
# NEVER spacewalk-common-channels [BOOT §3.2]. The commands are in PLAN §5.9 (commented out there too).
