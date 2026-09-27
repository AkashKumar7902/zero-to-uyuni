#!/usr/bin/env bash
# accept-loop.sh MINUTES — purge stale pending attendee keys once, then accept ONLY attendee sandbox keys, max CAP, for MINUTES.
# Never salt-key -A. [BOOT §5.2 #13]
# Game hooks (geeko-hq golden-hooks; each post is backgrounded with a 5-s limit, so the 5-s rhythm never waits for
# the game): "doors OPEN" first (the room's countdown lands on the real start), then the purged ids, then one
# "accepted" per key; "doors CLOSED" when the loop ends or is stopped. The block list is the game's own
# (deny-check.sh + deny.env, generated from the nickname guard): a name the game refuses is rejected here too.
set -uo pipefail; export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
RX='^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$'; CAP=${CAP:-60}; END=$(( $(date +%s) + 60*${1:-65} ))
# osas26_denied <id>: exit 0 = reject. Without the installed hooks, PLAN §5.11's short list still guards the doors.
# shellcheck source=deny-check.sh
if ! . "${DENY_DIR:-/usr/local/share/osas26}/deny-check.sh" 2>/dev/null; then
  DENY='fuck|shit|bitch|anjing|bangsat|kontol|memek|goblok|tolol'
  osas26_denied(){ [[ $1 =~ $DENY ]]; }
fi
k(){ kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
GP=${GAME_POST:-/usr/local/sbin/osas26-game-post}
gp(){ [ -x "$GP" ] && ( timeout 5 "$GP" "$1" >/dev/null 2>&1 & ); return 0; }
closed(){ [ -x "$GP" ] && timeout 5 "$GP" '{"t":"doors","state":"CLOSED"}' >/dev/null 2>&1; exit 0; }
trap closed EXIT; trap 'exit 0' TERM INT                        # systemd stop / RuntimeMaxSec: still say CLOSED
gp '{"t":"doors","state":"OPEN"}'
# One-time purge of keys that were pending BEFORE the window (early joiners, expired sandboxes): no ghost systems, no used-up cap.
# A live minion re-sends its key on its next auth retry (~10 s), so it re-appears as pending and is accepted below.
# The speaker's own knock is kept (review fix): the first pass at the doors accepts it before any attendee's join.sh
# can finish, so FIRST CONTACT (the callout on Akash's hut) always happens, and nobody else is ever "first".
SPEAKER_NICK=${SPEAKER_NICK:-akash}
purged=()
for id in $(k salt-key --out=json 2>/dev/null | jq -r '.minions_pre[]' | grep -E '^osas26-' | grep -vE "^osas26-${SPEAKER_NICK}-" || true); do
  k salt-key -y -d "$id" >/dev/null && echo "$(date +%T) purged   $id" && purged+=("$id"); done
[ ${#purged[@]} -gt 0 ] && gp "{\"t\":\"purged\",\"ids\":$(printf '%s\n' "${purged[@]}" | grep -E "$RX" | jq -R . | jq -sc .)}"
while [ "$(date +%s)" -lt "$END" ]; do
  keys=$(k salt-key --out=json 2>/dev/null) || { sleep 5; continue; }
  acc=$(jq -r '.minions[]' <<<"$keys" | grep -cE "$RX" || true)
  for id in $(jq -r '.minions_pre[]' <<<"$keys"); do
    if [[ $id =~ ^osas26- ]] && osas26_denied "$id"; then      # reject, so the minion stops retrying and the
      k salt-key -y -r "$id" >/dev/null && echo "$(date +%T) rejected $id"   # name never sits in the pending list
    elif [[ $id =~ $RX ]] && [ "$acc" -lt "$CAP" ]; then
      k salt-key -y -a "$id" >/dev/null && acc=$((acc+1)) && echo "$(date +%T) accepted $id" && gp "{\"t\":\"accepted\",\"id\":\"$id\"}"
    else echo "$(date +%T) ignored  $id"; fi
  done
  sleep "${ACCEPT_SLEEP:-5}"
done
