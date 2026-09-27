#!/usr/bin/env bash
# build.sh - HQ from zero, unattended (PLAN §5.10): 00-os-prep -> 10-rke2 -> 20-addons -> 30-uyuni -> 40-harden ->
# 50-content, then check.sh. Run it inside tmux ON THE VM, so an SSH drop cannot kill it halfway:
#   tmux new -d -s build 'read -p "Enter to start the build "; bash /root/zero-to-uyuni/lab/build.sh 2>&1 | tee /root/build.log'
# FROM=30 bash build.sh   resumes at a phase (the retry slot: fix, then re-run the failed phase on the same VM).
# Every phase is timed (seconds) into /root/osas26/build-phases.tsv; the fine-grained marks are in timings.tsv.
# The output carries no secrets (set +x everywhere; 50-content.sh never echoes the password): still run PLAN §5.0's
# cast check before committing a cast of it.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
[ "$(id -u)" = 0 ] || die "run as root"
install -d -m 0700 "$W"
FROM=${FROM:-00}
P=$W/build-phases.tsv
t build_start
b0=$(date +%s)
for s in 00-os-prep 10-rke2 20-addons 30-uyuni 40-harden 50-content; do
  [ "${s%%-*}" \< "$FROM" ] && { echo "--- skip $s (FROM=$FROM)"; continue; }
  echo; echo "=================== $s  ($(date -u +%T) UTC) ==================="
  s0=$(date +%s)
  if bash "$LAB/$s.sh"; then rc=0; else rc=$?; fi
  s1=$(date +%s); printf '%s\t%s\t%s\t%s\n' "$s" "$((s1 - s0))" "$rc" "$(date -u +%FT%TZ)" >> "$P"
  echo "--- $s: $((s1 - s0)) s, exit $rc"
  if [ "$rc" != 0 ]; then
    echo "BUILD STOPPED in $s (exit $rc). Fix it, then:  FROM=${s%%-*} bash $LAB/build.sh"; t "build_failed_$s"; exit "$rc"; fi
done
t build_done
echo; echo "=================== check.sh ==================="
bash "$LAB/check.sh"; crc=$?
echo; echo "=================== BUILD DONE in $(( $(date +%s) - b0 )) s (check.sh exit $crc) ==================="
column -t -s "$(printf '\t')" "$P" 2>/dev/null || cat "$P"
cat <<'EOF'

Next (PLAN §5.16.3, with Akash on SSH): the game hooks (geeko-hq golden-hooks/install.sh), game.env + game.hdr,
then the acceptance tests. Golden-only files by scp: /root/osas26/finale-aliases.sh, /root/osas26/credits-extra.txt.
The admin password is in /root/osas26/secrets.env: copy it to the password manager OFF the projector.
EOF
exit "$crc"
