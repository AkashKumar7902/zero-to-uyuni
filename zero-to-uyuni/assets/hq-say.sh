#!/usr/bin/env bash
# hq-say.sh welcome|promo - HQ (Uyuni) prints one message into every terminal of THIS sandbox.
# Uyuni runs it as a Salt remote command (as root). Read it: it only prints text.
# YOUR OWN HQ (solo.sh): your own master runs it the same way (salt <your id> cmd.run '/root/osas26/hq-say.sh welcome'),
# and then it tells the game "your own HQ ran a remote command" (the room's HQ is heard by its own listener instead).
[ -f "${SANDBOX_FLAG:-/etc/osas26-sandbox}" ] || exit 0
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh" 2>/dev/null
# shellcheck source=solo.sh
. "$D/solo.sh" 2>/dev/null
crew=$(cut -d- -f2 "${ID_FILE:-/etc/osas26-id}" 2>/dev/null || hostname)
solo=""; solo_on 2>/dev/null && solo=1
case "${1:-welcome}:$solo" in
  welcome:)  c='1;33'; msg="[HQ] Hello, crew $crew. Uyuni here, talking through Salt, as root. I only print text today. Orders coming. In 2 minutes type: cat /etc/motd";;
  promo:)    c='1;36'; msg="[HQ] Promotions are in, crew $crew. Salt wrote your card again. Type: cat /etc/motd";;
  welcome:1) c='1;33'; msg="[YOUR HQ] Hello, crew $crew. Your own Salt master here, talking through Salt, as root. I only print text. Next: your crew card.";;
  promo:1)   c='1;36'; msg="[YOUR HQ] Promotions are in, crew $crew. Salt wrote your card again. Type: cat /etc/motd";;
  *) echo "usage: hq-say.sh welcome|promo"; exit 1;;
esac
for t in /dev/pts/[0-9]*; do printf '\n\033[%sm%s\033[0m\n' "$c" "$msg" 2>/dev/null >"$t"; done
if [ -n "$solo" ]; then
  mkdir -p "${ACH_DIR:-/etc/osas26}" 2>/dev/null && touch "${ACH_DIR:-/etc/osas26}/solo.cmd" 2>/dev/null
  game_post_sync solo '{"step":"cmd"}' 2>/dev/null
fi
echo "HQ message delivered to $crew"
