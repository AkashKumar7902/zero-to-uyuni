#!/usr/bin/env bash
# lab/runner/hooks.sh HOOKS_DIR off|on [ROOM] - RUNNER-HQ: geeko-hq's golden hooks on this HQ (geeko-hq DEPLOY §6.1,
# the runner's version). HOOKS_DIR is a checkout of geeko-hq's golden-hooks/ with deny.env generated next to it.
#   off  installed, GAME_OFF=1, nothing enabled (the default: HQ never talks to the game)
#   on   game.hdr from $GOLDEN_TOKEN (the environment only: never an argument, never printed), game.env with GAME_OFF=0,
#        then d-game-on (fleet-sync + fleet-listen) and T-H1 (one ping; 202 expected). The drill timers stay unarmed.
# ROOM: auto (the default: the live room applies inside the show window and forwards to the console's GOLDEN target
#       outside it) or a rehearsal room reh-MMDD-n (posts go straight there). Never "osas26" by name.
set -euo pipefail
H=${1:?hooks dir}; MODE=${2:-off}; ROOM=${3:-auto}
W=/root/osas26; URL=${GAME_URL_FOR_HQ:-https://geeko-hq.pages.dev}
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
[[ $ROOM == auto || $ROOM =~ ^reh-[0-9]{4}-[0-9]+$ ]] || { echo "ROOM must be auto or reh-MMDD-n (never the live room by name)"; exit 1; }
[ -s "$H/deny.env" ] || { echo "deny.env missing in $H (node golden-hooks/make-deny-env.mjs > golden-hooks/deny.env)"; exit 1; }
bash "$H/install.sh" /root/zero-to-uyuni/lab
# the two source lines of DEPLOY §6.1 step 4 (the repo's aliases.sh and check.sh already carry them)
grep -qF '/usr/local/share/osas26/aliases-game.sh' /root/zero-to-uyuni/lab/aliases.sh || echo '. /usr/local/share/osas26/aliases-game.sh' >> /root/zero-to-uyuni/lab/aliases.sh
grep -qF '/usr/local/share/osas26/check-game.sh' /root/zero-to-uyuni/lab/check.sh || echo '. /usr/local/share/osas26/check-game.sh' >> /root/zero-to-uyuni/lab/check.sh
umask 077
if [ "$MODE" = on ]; then
  [ -n "${GOLDEN_TOKEN:-}" ] || { echo "game=on needs the GOLDEN_TOKEN secret; installed with GAME_OFF=1 instead"; MODE=off; }
fi
if [ "$MODE" = on ]; then
  printf 'Authorization: Bearer %s\n' "$GOLDEN_TOKEN" > "$W/game.hdr"; chmod 600 "$W/game.hdr"
  curl -sf -m 10 "$URL/api/health" | jq -e .ok >/dev/null || { echo "the game does not answer at $URL/api/health: GAME_OFF=1"; MODE=off; }
fi
if [ "$MODE" = on ]; then
  printf 'GAME_URL=%s\nGAME_ROOM=%s\nGAME_HDR=%s\nGAME_OFF=0\n' "$URL" "$ROOM" "$W/game.hdr" > "$W/game.env"
  systemctl enable --now osas26-fleet-sync osas26-fleet-listen            # = d-game-on
  systemd-run --wait -q -u osas26-th1 /usr/local/sbin/osas26-game-post '{"t":"ping"}'
  echo "T-H1: $(tail -n 1 "$W/game-post.log")  (want 202)"
else
  printf 'GAME_URL=%s\nGAME_ROOM=auto\nGAME_HDR=%s\nGAME_OFF=1\n' "$URL" "$W/game.hdr" > "$W/game.env"
  echo "hooks installed with GAME_OFF=1 (nothing enabled)"
fi
chmod 600 "$W/game.env"
