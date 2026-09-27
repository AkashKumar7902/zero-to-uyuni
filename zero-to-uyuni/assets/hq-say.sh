#!/usr/bin/env bash
# hq-say.sh welcome|promo - HQ (Uyuni) prints one message into every terminal of THIS sandbox.
# Uyuni runs it as a Salt remote command (as root). Read it: it only prints text.
[ -f /etc/osas26-sandbox ] || exit 0
crew=$(cut -d- -f2 /etc/osas26-id 2>/dev/null || hostname)
case "${1:-welcome}" in
  welcome) c='1;33'; msg="[HQ] Hello, crew $crew. Uyuni here, talking through Salt, as root. I only print text today. Orders coming. In 2 minutes type: cat /etc/motd";;
  promo)   c='1;36'; msg="[HQ] Promotions are in, crew $crew. Salt wrote your card again. Type: cat /etc/motd";;
  *) echo "usage: hq-say.sh welcome|promo"; exit 1;;
esac
for t in /dev/pts/[0-9]*; do printf '\n\033[%sm%s\033[0m\n' "$c" "$msg" 2>/dev/null >"$t"; done
echo "HQ message delivered to $crew"
