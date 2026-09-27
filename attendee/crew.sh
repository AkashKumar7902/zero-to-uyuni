#!/usr/bin/env bash
# crew.sh CODE [ROOM] - link THIS sandbox to your crew in the Geeko HQ game (10 seconds, once; the first line of Level 1).
# Your game page (laptop or phone) shows your 4-character crew code after check-in. After linking, your REAL work shows
# on the big screen: the blueprint you render, the machine you join, the orders you receive, the incident you fix.
# Only "done" facts are sent, never what you type (answers and evidence words stay here). Not linked? Everything works.
# ROOM is only for rehearsals (the game page shows the exact line to copy). Needs: curl. No jq.
set -u
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"

code=$(printf '%s' "${1:-}" | tr 'a-z' 'A-Z' | tr -cd 'ACDEFHJKMNPRTWXY3479')
room=${2:-}
if [ ${#code} -ne 4 ]; then
  echo "Usage: /root/osas26/crew.sh <your crew code>   (4 letters and digits, on your game page)"; exit 1; fi
if [ -n "$room" ] && ! [[ $room =~ ^(osas26|reh-[a-z0-9-]{1,24})$ ]]; then
  echo "That room name looks wrong. Copy the whole line from your game page."; exit 1; fi

url=$(sed -n 's/^GAME_URL=//p' "$(game_server_env)" 2>/dev/null | head -1)
case "$url" in https://*|http://localhost:*|http://127.0.0.1:*) ;; *)
  echo "No game address yet. Keep playing: run crew.sh again later, nothing is lost."; exit 0 ;; esac

echo "[1/2] Your sandbox calls the game server (outbound HTTPS, like every call your sandbox makes today)..."
resp=$(curl -sS -m 8 -w '\n%{http_code}' -X POST "$url/api/sb/link${room:+?room=$room}" \
            -H 'Content-Type: application/json' --data-binary "{\"code\":\"$code\"}" 2>/dev/null)
status=${resp##*$'\n'}; body=${resp%$'\n'*}
case "$status" in
  201|200) ;;
  404) echo "      That code did not match a crew. Check it on your game page, then try again."; exit 1 ;;
  429) echo "      The game is busy. Try again in a minute."; exit 0 ;;
  423) echo "      The game is not open right now. Your lab works without it."; exit 0 ;;
  *)   echo "      No answer. Keep playing: run crew.sh again later, nothing is lost."; exit 0 ;;
esac
tok=$(printf '%s' "$body" | sed -nE 's/.*"token":"([A-Za-z0-9._-]{16,200})".*/\1/p')
crew=$(printf '%s' "$body" | sed -nE 's/.*"crew":"([a-z0-9]{2,12})".*/\1/p')
got_room=$(printf '%s' "$body" | sed -nE 's/.*"room":"(osas26|reh-[a-z0-9-]{1,24})".*/\1/p')
if [ -z "$tok" ] || [ -z "$crew" ]; then
  echo "      No answer. Keep playing: run crew.sh again later, nothing is lost."; exit 0; fi

( umask 077
  mkdir -p "$(dirname "$GAME_ENV")" "$(dirname "$GAME_HDR")"
  printf 'GAME_URL=%s\nGAME_ROOM=%s\nGAME_CREW=%s\n' "$url" "${got_room:-${room:-osas26}}" "$crew" > "$GAME_ENV"
  printf 'Authorization: Bearer %s\n' "$tok" > "$GAME_HDR" )
echo "[2/2] Saved your crew ticket (only root can read it)."
echo
printf '  \033[1;36m[game] Crew %s is linked. Your real work shows on the big screen now.\033[0m\n\n' "$crew"
game_post link '{}'
# Linked late? Tell the game what this sandbox already did (each fact is checked here, now; idempotent).
game_detach bash "$D/probe.sh" replay
exit 0
