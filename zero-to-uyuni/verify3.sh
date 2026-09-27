#!/usr/bin/env bash
# Level 3 CHECK: the live-edited order reached this machine's /etc/motd, or the helper-approved skip marker exists.
# Tells the game whether the card knew THIS machine's Level 1, and the lines this machine dialled (held for PROOF).
D=$(dirname "$0"); CHECK=${CHECK_FILE:-/root/.check}; MOTD=${MOTD_FILE:-/etc/motd}
# shellcheck source=game.sh
. "$D/game.sh"
if grep -qF 'ORDER FROM HQ: find out what happened' "$MOTD" 2>/dev/null; then
  game_detach bash -c "bash '$D/probe.sh' card; bash '$D/probe.sh' lines"
  "$D/achieve.sh" motd "Orders received: Uyuni changed your machine."
else
  test -e /tmp/osas26-skip3 || { echo "No orders yet: wait for HQ, then cat /etc/motd (or ask a helper)" > "$CHECK"; exit 1; }
fi
