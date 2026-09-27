#!/usr/bin/env bash
# lab/runner/sample.sh [SECONDS] - RUNNER-HQ: resource samples every SECONDS (default 10) into
# /root/osas26/runner/samples.tsv: UTC time, CPU busy % since the last sample, load1, memory used/available MiB,
# swap used MiB, / free GB, and the biggest process by RSS. Runs as a transient unit for the whole job.
set -uo pipefail
S=${1:-10}; F=/root/osas26/runner/samples.tsv; install -d -m 0700 /root/osas26/runner
[ -s "$F" ] || printf 'utc\tcpu_busy_pct\tload1\tmem_used_mib\tmem_avail_mib\tswap_used_mib\troot_free_gb\ttop_rss\n' > "$F"
read -r _ u n s i w q sq st _ < /proc/stat; pb=$((u + n + s + q + sq + st)); pt=$((pb + i + w))
while sleep "$S"; do
  read -r _ u n s i w q sq st _ < /proc/stat; b=$((u + n + s + q + sq + st)); t=$((b + i + w))
  cpu=$(( t > pt ? 100 * (b - pb) / (t - pt) : 0 )); pb=$b; pt=$t
  m=$(free -m | awk '/^Mem:/{u=$3; a=$7} /^Swap:/{sw=$3} END{printf "%d\t%d\t%d", u, a, sw}')
  top=$(ps -eo rss=,comm= --sort=-rss | head -1 | awk '{printf "%s:%dM", $2, $1/1024}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%T)" "$cpu" "$(cut -d' ' -f1 /proc/loadavg)" "$m" "$(df -BG --output=avail / | tail -1 | tr -dc 0-9)" "$top" >> "$F"
done
