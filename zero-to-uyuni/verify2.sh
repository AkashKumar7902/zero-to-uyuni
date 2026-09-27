#!/usr/bin/env bash
# Level 2 CHECK: join.sh ran. Passes even if port 4506 is blocked (never gate on the infrastructure; AMBER-E puzzle).
# In the background (never holding CHECK): once HQ trusts this machine, count the lines it dialled (LD-7).
D=$(dirname "$0"); CHECK=${CHECK_FILE:-/root/.check}
# shellcheck source=game.sh
. "$D/game.sh"
test -s "${ID_FILE:-/etc/osas26-id}" || { echo "Run /root/osas26/join.sh first" > "$CHECK"; exit 1; }
game_detach bash "$D/probe.sh" lines --wait
"$D/achieve.sh" join "Onboarded: HQ knows your machine."
