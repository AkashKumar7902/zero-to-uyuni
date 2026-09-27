#!/usr/bin/env bash
# cleanup.sh - between rehearsals, after the Oct 2 helper window, and on the evening of the session (PLAN §5.11):
# deletes every fleet system and every osas26-* Salt key, resets leap-b, and clears the game state files.
# The counts guard comes first: on the day, record the counts (d-savecounts) BEFORE this; rehearsals use FORCE=1.
# Run it after the sandboxes are gone: a live minion re-sends its key within ~10 s (the accept loop purges stale
# pending keys when the doors open, so that is harmless).
[ -e /root/osas26/evidence-count ] && [ ! -e /root/osas26/counts-saved ] && [ "${FORCE:-}" != 1 ] && { echo 'Record the counts first: d-savecounts (or FORCE=1 for a rehearsal)'; exit 1; }
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
. "$W/secrets.env"
kx(){ kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
sc(){ kx spacecmd -y -u admin -p "$ADMIN_PASS" -- "$@"; }
cnt(){ sc group_listsystems osas26-fleet 2>/dev/null | tr '\r' '\n' | grep -c '^osas26-' || true; }
n=$(cnt)
if [ "$n" -gt 0 ]; then
  sc system_delete -c FORCE_DELETE group:osas26-fleet             # spacecmd expands group:NAME; -y confirms [R5]
  # system_delete only SCHEDULES the removal (it also drops the Salt keys): wait until the group is empty (rehearsal F7)
  for _ in $(seq 30); do sc clear_caches >/dev/null 2>&1; [ "$(cnt)" = 0 ] && break; sleep 2; done
  echo "deleted $n fleet system(s) (group now $(cnt))"
else echo "no fleet systems"; fi
for id in $(kx salt-key --out=json 2>/dev/null | jq -r '(.minions + .minions_pre + .minions_rejected + .minions_denied)[]' | grep -E '^osas26-' || true); do
  kx salt-key -y -d "$id" >/dev/null && echo "deleted key $id"; done
if grep -qE '^Host[[:space:]]+leap-b([[:space:]]|$)' /root/.ssh/config 2>/dev/null; then "$Z2U/clients/reset-leap-b.sh"
else echo "leap-b: no 'Host leap-b' in /root/.ssh/config (skipped)"; fi
rm -f "$W"/{ach.log,evidence-count,room-status,outage-roster,outage-n,raffle-n,counts-saved,.registered,.registered-ids}
echo "game state files cleared"
sc clear_caches >/dev/null 2>&1   # spacecmd caches the system list in the container: without this it keeps showing deleted systems (F7)
echo "systems left in Uyuni: $(sc system_list 2>/dev/null | tr '\r' '\n' | grep -cE ' : [0-9]+$' || true)"
