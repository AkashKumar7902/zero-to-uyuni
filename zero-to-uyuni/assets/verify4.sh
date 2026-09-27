#!/usr/bin/env bash
# Level 4 CHECK: the EFFECTIVE master is HQ again, no REJECT rule, the minion runs AND was restarted after the newest
# edit of ANY minion.d file; or the helper skip marker. (LD-1: Uyuni's susemanager.conf overrides osas26.conf, so
# "effective" = what Salt itself reports, the command the runbook's step 1 teaches.)
# The game hears the facts (counts only): how many crews met the "restart trap" (config fixed, minion not restarted:
# the most common real mistake, shown as normal, never by name), and the fixed incident. HQ decides the relight.
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
MD=${MINION_D:-/etc/venv-salt-minion/minion.d}
FQDN_FILE=${FQDN_FILE:-/etc/osas26-fqdn}
CHECK=${CHECK_FILE:-/root/.check}
SALT=${SALT_CALL:-venv-salt-call}
SKIP=${SKIP4:-/tmp/osas26-skip4}
ACH=${ACH_DIR:-/etc/osas26}
eff(){ timeout 20 "$SALT" --local config.get master 2>/dev/null | sed -n '2p' | tr -d ' '; }
if [ ! -e "$SKIP" ]; then
  st=$(date -d "$(systemctl show -p ActiveEnterTimestamp --value venv-salt-minion 2>/dev/null)" +%s 2>/dev/null || echo 0)
  # the attendee's edits only: Salt itself rewrites minion.d/_schedule.conf (any _*.conf) ~2 s after EVERY start, so
  # counting it made this CHECK fail forever on a real registered minion (laptop dress rehearsal, 2026-09-27)
  newest=$(stat -c %Y "$MD"/[!_]*.conf 2>/dev/null | sort -n | tail -1)
  if [ "${newest:-0}" -gt "$st" ]; then
    echo 'Config fixed; now restart the minion (runbook step 5): systemctl restart venv-salt-minion' > "$CHECK"
    mkdir -p "$ACH" 2>/dev/null
    [ -e "$ACH/trap.sent" ] || { touch "$ACH/trap.sent" 2>/dev/null; game_post l4.restart_trap '{}'; }
    exit 1
  fi
fi
if [ "$(eff)" = "$(cat "$FQDN_FILE" 2>/dev/null)" ] \
   && ! iptables -C OUTPUT -p tcp --dport 4506 -j REJECT 2>/dev/null \
   && systemctl is-active --quiet venv-salt-minion; then
  "$D/achieve.sh" doctor "Incident closed: you brought your machine back."
  game_post l4.fixed "$(bash "$D/probe.sh" incident)"
  exit 0
fi
test -e "$SKIP" && exit 0
echo "Still dark: walk the runbook (config, DNS, port, log, restart), or /root/osas26/fix.sh once the speaker allows it" > "$CHECK"
exit 1
