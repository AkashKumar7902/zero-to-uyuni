#!/usr/bin/env bash
# Level 2 CHECK: join.sh ran. Passes even if port 4506 is blocked (never gate on the infrastructure).
# In the background (never holding CHECK): once HQ trusts this machine, count the lines it dialled (LD-7).
# YOUR OWN HQ (solo.sh): accepting the key is YOUR job today, so CHECK waits for your own master's yes (salt-key -a),
# and then tells the game "your own HQ accepted your key".
D=$(dirname "$0"); CHECK=${CHECK_FILE:-/root/.check}
[ -e "$D/game.sh" ] || D=/root/osas26   # Killercoda may run a CHECK from another directory: the kit lives in /root/osas26 (UBR 5.1)
# shellcheck source=game.sh
. "$D/game.sh"
# shellcheck source=solo.sh
. "$D/solo.sh"
test -s "${ID_FILE:-/etc/osas26-id}" || { echo "Run /root/osas26/join.sh first" > "$CHECK"; exit 1; }
if solo_on; then
  id=$(tr -cd 'a-z0-9-' < "${ID_FILE:-/etc/osas26-id}")
  solo_accepted "$id" || { echo "Your own HQ is waiting for YOUR yes: salt-key -a $id" > "$CHECK"; exit 1; }
  game_post solo '{"step":"trusted"}'
  "$D/achieve.sh" join "Onboarded: your own HQ trusts your machine."
  exit 0
fi
game_detach bash "$D/probe.sh" lines --wait
"$D/achieve.sh" join "Onboarded: HQ knows your machine."
