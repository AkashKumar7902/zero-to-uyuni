#!/usr/bin/env bash
# Level 3 CHECK: the live-edited order reached this machine's /etc/motd, or the helper-approved skip marker exists.
# Tells the game whether the card knew THIS machine's Level 1, and the lines this machine dialled (held for PROOF).
# YOUR OWN HQ (solo.sh): the same card, the same order line; you edited the recipe and applied it yourself, so the game
# also hears "your own HQ wrote your card".
D=$(dirname "$0"); CHECK=${CHECK_FILE:-/root/.check}; MOTD=${MOTD_FILE:-/etc/motd}
[ -e "$D/game.sh" ] || D=/root/osas26   # Killercoda may run a CHECK from another directory: the kit lives in /root/osas26 (UBR 5.1)
# shellcheck source=game.sh
. "$D/game.sh"
# shellcheck source=solo.sh
. "$D/solo.sh"
if grep -qF 'ORDER FROM HQ: find out what happened' "$MOTD" 2>/dev/null; then
  game_detach bash -c "bash '$D/probe.sh' card; bash '$D/probe.sh' lines"
  if solo_on; then game_post solo '{"step":"orders"}'; "$D/achieve.sh" motd "Orders received: your own HQ changed your machine."
  else "$D/achieve.sh" motd "Orders received: Uyuni changed your machine."; fi
else
  if solo_on; then
    test -e /tmp/osas26-skip3 || { echo "No order yet: change the order line in your recipe, then apply it (Level 3, your own HQ)" > "$CHECK"; exit 1; }
  else
    test -e /tmp/osas26-skip3 || { echo "No orders yet: wait for HQ, then cat /etc/motd (or ask a helper)" > "$CHECK"; exit 1; }
  fi
fi
