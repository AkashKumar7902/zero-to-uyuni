#!/usr/bin/env bash
# break.sh [dns|port] - the incident drill. Random fault if no argument; records the mode for fix.sh and the crew card.
# LD-1: after registration Uyuni writes minion.d/susemanager.conf with its own "master:" line, and Salt lets the
# alphabetically LAST file win. So the DNS fault edits EVERY master: line, and the EFFECTIVE master (what the minion
# really uses) is wrong: the node really goes dark. The game hears only the fault's mode (never a name).
# YOUR OWN HQ (solo.sh): the same two faults cut the minion off from YOUR master (door 4506 on 127.0.0.1).
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
# shellcheck source=solo.sh
. "$D/solo.sh"
MD=${MINION_D:-/etc/venv-salt-minion/minion.d}
BREAK_FILE=${BREAK_FILE:-/root/.osas26-break}
m="${1:-$([ $((RANDOM%2)) = 0 ] && echo dns || echo port)}"
case "$m" in dns|port) ;; *) echo "usage: /root/osas26/break.sh [dns|port]"; exit 1 ;; esac
command -v iptables >/dev/null || m=dns
# once is the drill: a second run (a worried click on the first COPY) would stack a second port rule
if [ -s "$BREAK_FILE" ]; then
  echo "break.sh already ran on this machine ($(tr -cd 'a-z' < "$BREAK_FILE")). No need to run it again: it is a drill."
  echo "Now the runbook: 1 config -> 2 DNS -> 3 port -> 4 log -> 5 restart the minion."
  exit 0
fi
if [ "$m" = dns ]; then
  for f in $(grep -l '^master:' "$MD"/*.conf 2>/dev/null); do
    sed -i 's/^master: .*/master: uyuni.osas26.invalid/' "$f"      # .invalid never resolves (RFC 6761)
  done
fi
[ "$m" = port ] && iptables -I OUTPUT -p tcp --dport 4506 -j REJECT
echo "$m" > "$BREAK_FILE"; systemctl restart venv-salt-minion
game_post l4.break "{\"mode\":\"$m\"}"
who=HQ; solo_on && who="Your own HQ"
printf '\n\033[1;31m*** PAGER ***  INC-%03d  %s lost contact with %s. Drill! Now you know how Lintang felt at 03:12.\033[0m\n' \
  "$((RANDOM%1000))" "$who" "$(cat /etc/osas26-id 2>/dev/null || hostname)"
echo "Runbook (also on the projector): 1 config -> 2 DNS -> 3 port -> 4 log -> 5 restart the minion. Fix it by hand."
echo "/root/osas26/fix.sh is allowed only when the speaker says \"fix.sh allowed\"."
exit 0
