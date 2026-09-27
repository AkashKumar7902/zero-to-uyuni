#!/usr/bin/env bash
# lab/runner/gate.sh - RUNNER-HQ v7: should THIS hq run build an HQ? (hq.yml's first job; GH_TOKEN with actions: read)
# Prints go=true|false (for $GITHUB_OUTPUT) and one plain line why. Two rules:
#   1. the Oct 3 schedule (cron 05:37 UTC = 12:37 WIB) builds only on 2026-10-03 and only if it starts by 06:15 UTC
#      (13:15 WIB): GitHub may start a scheduled run late, or not at all; a late one never makes a second HQ, and the
#      13:00 WIB phone tap covers a missing one;
#   2. ONE HQ: a run (any event) that was created while another hq run of this repo was still queued or running is a
#      duplicate and builds nothing. With `concurrency: hq` a duplicate first waits in the queue behind the running HQ,
#      then starts when that HQ ends and exits here in seconds. So a second tap (or the late cron) never builds a second
#      HQ, not even hours later; a tap made AFTER the old run ended (it failed, or was cancelled) builds a fresh HQ.
# If GitHub's API cannot be read, the run builds (a show-day tap must never be blocked by the check itself).
set -uo pipefail
R=${GITHUB_REPOSITORY:?}; ME=${GITHUB_RUN_ID:?}; EV=${GITHUB_EVENT_NAME:-workflow_dispatch}
now=$(date -u +%s)
out(){ echo "go=$1"; echo "why=$2"; echo "$2" >&2; exit 0; }
if [ "$EV" = schedule ]; then
  [ "$(date -u +%F)" = "${SHOW_DATE_UTC:-2026-10-03}" ] || out false "schedule: today is not the show day ($(date -u +%F)): nothing to build"
  lim=$(date -u -d "${SHOW_DATE_UTC:-2026-10-03} ${LATEST_START_UTC:-06:15}" +%s)
  [ "$now" -le "$lim" ] || out false "schedule: started $(date -u +%H:%M) UTC, after the 06:15 UTC (13:15 WIB) limit: a late cron builds nothing (start by hand if no HQ runs)"
fi
me=$(gh api "repos/$R/actions/runs/$ME" --jq .created_at 2>/dev/null) || out true "the run list could not be read: building (fail-open)"
runs=$(gh api "repos/$R/actions/workflows/hq.yml/runs?per_page=30" 2>/dev/null) || out true "the run list could not be read: building (fail-open)"
dup=$(jq -r --arg me "$me" --argjson id "$ME" '
  [.workflow_runs[] | select(.id != $id and .created_at < $me and .status != "completed")]
  | first | if . == null then "" else "\(.id) (\(.event), \(.status), created \(.created_at))" end' <<<"$runs")
[ -z "$dup" ] || out false "duplicate: hq run $dup is still queued or running: ONE HQ at a time, nothing to build"
# a run that has ENDED since: was it still running when this one was created? (its jobs' completed_at; a run's
# updated_at alone can move later, e.g. when its logs are deleted)
for id in $(jq -r --arg me "$me" --argjson id "$ME" '.workflow_runs[] | select(.id != $id and .created_at < $me and .status == "completed" and .updated_at > $me) | .id' <<<"$runs"); do
  end=$(gh api "repos/$R/actions/runs/$id/jobs" --jq '[.jobs[].completed_at | select(. != null)] | max // ""' 2>/dev/null) || continue
  [ -n "$end" ] && [[ $end > $me ]] && out false "duplicate: hq run $id was still running when this run was created ($me; it ended $end): ONE HQ at a time, nothing to build"
done
out true "building HQ (event $EV, created $me)"
