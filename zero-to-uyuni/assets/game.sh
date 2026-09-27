#!/usr/bin/env bash
# game.sh - SOURCE it. The sandbox's link to the Geeko HQ game (GAME-BIBLE §7.5, SPEC §10).
#   game_post KIND DATA        tell the game a REAL fact about THIS sandbox; backgrounded, never blocks, never fails
#   game_post_sync KIND DATA   the same, but waits up to 4 s; returns 0 only if the game took it (for a [game] line)
#   game_flush                 re-send queued events as one batch (runs after every successful post)
#   game_detach CMD...         run CMD fully detached (a Killercoda CHECK never waits for it)
#   game_server_env            refresh server.env (GitHub first, the bundled copy second); prints its path
# Rules (tested in kit/test/run-all.sh):
#   - the lab NEVER depends on the game: no token (crew.sh never ran) = a quiet no-op; any failure = exit 0;
#   - KIND must be on the allow-list below; DATA must be a small JSON object built by OUR scripts from fixed words,
#     numbers and checked ids. Nothing a person typed (answers, evidence words, prompts) ever leaves the sandbox;
#   - offline: the event waits in an outbox (max 50 lines, max 2 h old) and goes out with the next success;
#   - the token never appears on a command line: curl reads it from a root-only header file (-H @file).
# No jq on the sandbox: sed and printf only.
GAME_ENV=${GAME_ENV:-/etc/osas26/game.env}          # written by crew.sh: GAME_URL, GAME_ROOM, GAME_CREW
GAME_HDR=${GAME_HDR:-/etc/osas26/game.hdr}          # written by crew.sh: "Authorization: Bearer sb.<room>.<secret>"
GAME_OUTBOX=${GAME_OUTBOX:-/etc/osas26/outbox}
GAME_KINDS=' link l1.render l1.evidence l2.join l2.lines l3.card l4.break l4.fixed l4.restart_trap quest replay '
GAME_MAX_AGE=7200                                   # the server drops older outbox events anyway (SPEC §5.9)

_game_load() {
  [ -r "$GAME_ENV" ] && [ -r "$GAME_HDR" ] || return 1
  GAME_URL=$(sed -n 's/^GAME_URL=//p' "$GAME_ENV" | head -1)
  # shellcheck disable=SC2034  # read by the scripts that source this file (join.sh prints it)
  GAME_CREW=$(sed -n 's/^GAME_CREW=//p' "$GAME_ENV" | head -1)
  case "$GAME_URL" in https://*|http://localhost:*|http://127.0.0.1:*) return 0 ;; esac
  return 1
}

# One POST. Prints the HTTP status (000 = no answer). The body goes in on stdin, the token from the header file.
_game_send() {
  curl -sS -m "${2:-3}" -o /dev/null -w '%{http_code}' -X POST "$GAME_URL/api/sb/event" \
       -H @"$GAME_HDR" -H 'Content-Type: application/json' --data-binary @- <<<"$1" 2>/dev/null || true
}

# Only fixed-shape JSON leaves the sandbox: known keys, and values that are numbers, booleans or short words made of
# letters, digits and : . _ - (ids, modes, fingerprint tails). A sentence someone typed can never pass this, even if a
# future script tried to send one.
GAME_KEYS=' pvcs source sealed case minion_id port4506 out4505 out4506 listen order box_matches_machine mode master_ok port_rule minion_active id tier fp replay '
_game_safe() {
  local re='^\{("[a-z0-9_]+":("[A-Za-z0-9:._-]{1,40}"|[0-9]{1,4}|true|false),?)*\}$' k
  [[ $1 =~ $re ]] && [ "${1: -2:1}" != , ] || return 1
  for k in $(printf '%s' "$1" | grep -oE '"[a-z0-9_]+":' | tr -d '":'); do
    case "$GAME_KEYS" in *" $k "*) ;; *) return 1 ;; esac
  done
}

_game_line() { printf '{"kind":"%s","t":%s,"data":%s}' "$1" "$(date +%s)" "$2"; }

# The outbox is shared by background posts: a mkdir lock (portable, no flock) guards every read and write of it.
_game_lock() {
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do mkdir "$GAME_OUTBOX.lock" 2>/dev/null && return 0; sleep 0.2; done
  rmdir "$GAME_OUTBOX.lock" 2>/dev/null; mkdir "$GAME_OUTBOX.lock" 2>/dev/null   # a stale lock after 2 s: take it
}
_game_unlock() { rmdir "$GAME_OUTBOX.lock" 2>/dev/null; }

_game_queue() {   # LINE... -> appended; the outbox keeps the newest 50
  mkdir -p "$(dirname "$GAME_OUTBOX")" 2>/dev/null || return 0
  _game_lock
  printf '%s\n' "$@" >> "$GAME_OUTBOX"
  tail -n 50 "$GAME_OUTBOX" > "$GAME_OUTBOX.t" 2>/dev/null && mv "$GAME_OUTBOX.t" "$GAME_OUTBOX"
  _game_unlock
}

# 2xx = taken. 401 = the token was revoked (UNLINK on the game page) or its room is gone: forget it, never retry.
# Validation errors are dropped (the same event cannot pass later); 429, 5xx and "no answer" are queued.
_game_verdict() {
  case "$1" in
    2??) return 0 ;;
    401) rm -f "$GAME_HDR" "$GAME_ENV" 2>/dev/null; return 2 ;;
    400|413|415|422) return 2 ;;
    *) return 1 ;;
  esac
}

game_flush() {
  _game_load || return 0
  [ -s "$GAME_OUTBOX" ] || return 0
  local now line t keep=()
  now=$(date +%s)
  _game_lock
  while IFS= read -r line; do
    t=$(printf '%s' "$line" | sed -n 's/^{"kind":"[a-z0-9._]*","t":\([0-9]*\),.*/\1/p')
    [ -n "$t" ] && [ $((now - t)) -le $GAME_MAX_AGE ] && keep+=("$line")
  done < "$GAME_OUTBOX"
  : > "$GAME_OUTBOX"
  _game_unlock
  [ ${#keep[@]} -gt 0 ] || return 0
  local joined code; joined=$(IFS=,; printf '%s' "${keep[*]}")
  code=$(_game_send "{\"events\":[$joined]}" 5)
  _game_verdict "$code"
  [ $? = 1 ] && _game_queue "${keep[@]}"
  return 0
}

_game_post_now() {   # KIND DATA TIMEOUT -> 0 taken, 1 queued, 2 dropped
  local line code v
  line=$(_game_line "$1" "$2")
  code=$(_game_send "$line" "$3")
  _game_verdict "$code"; v=$?
  [ $v = 0 ] && game_flush
  [ $v = 1 ] && _game_queue "$line"
  return $v
}

_game_ok() {   # the allow-list and the shape check come before anything else
  case "$GAME_KINDS" in *" $1 "*) ;; *) return 1 ;; esac
  _game_safe "$2"
}

game_post() {
  local kind=$1 data=${2:-'{}'}
  _game_ok "$kind" "$data" && _game_load || return 0
  ( _game_post_now "$kind" "$data" 3 ) >/dev/null 2>&1 &
  return 0
}

game_post_sync() {
  local kind=$1 data=${2:-'{}'}
  _game_ok "$kind" "$data" && _game_load || return 1
  _game_post_now "$kind" "$data" 4 >/dev/null 2>&1
}

game_detach() { ( "$@" </dev/null >/dev/null 2>&1 & ) ; }

# server.env is the one place that says where HQ and the game live (a rebuild or a new URL is a git push).
game_server_env() {
  local d out=${SERVER_ENV_FILE:-/tmp/server.env}
  local url=${SERVER_ENV_URL:-https://raw.githubusercontent.com/AkashKumar7902/zero-to-uyuni/main/attendee/server.env}
  d=$(dirname "${BASH_SOURCE[0]}")
  if curl -fsS --max-time 10 -o "$out.new" "$url" 2>/dev/null && grep -q '^FQDN=' "$out.new"; then
    mv "$out.new" "$out"
  else
    rm -f "$out.new"; cp "$d/server.env" "$out" 2>/dev/null
  fi
  echo "$out"
}
