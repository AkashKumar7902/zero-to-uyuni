#!/usr/bin/env bash
# fix.sh - the runbook, automated (allowed when the speaker says "fix.sh allowed": real SREs use runbooks).
# LD-1: restore EVERY master: line in minion.d (Uyuni's susemanager.conf too), drop the port rule, restart the minion.
# verify4.sh (the Level 4 CHECK) tells the game afterwards; HQ itself sees the minion start and call again.
# YOUR OWN HQ (solo.sh): the same runbook; the address it restores is your own master's (join.sh saved it).
# shellcheck source=solo.sh
. "$(dirname "$0")/solo.sh"
MD=${MINION_D:-/etc/venv-salt-minion/minion.d}
FQDN_FILE=${FQDN_FILE:-/etc/osas26-fqdn}
fq=$(cat "$FQDN_FILE" 2>/dev/null) || { echo "No HQ address saved yet: run /root/osas26/join.sh first."; exit 1; }
for f in $(grep -l '^master:' "$MD"/*.conf 2>/dev/null); do sed -i "s/^master: .*/master: $fq/" "$f"; done
for _ in 1 2 3 4 5 6 7 8; do iptables -D OUTPUT -p tcp --dport 4506 -j REJECT 2>/dev/null || break; done   # every copy of the rule
systemctl restart venv-salt-minion
if solo_on; then echo "fixed - press CHECK, then ask your own HQ (in ~10 s): salt $(cat "${ID_FILE:-/etc/osas26-id}" 2>/dev/null) test.ping"
else echo "fixed - watch the projector"; fi
