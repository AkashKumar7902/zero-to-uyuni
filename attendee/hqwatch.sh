#!/usr/bin/env bash
# hqwatch.sh ID IP CREW - the HQ table's safety net. join.sh --hq starts it in the background; a sandbox on its own HQ
# (MODE=solo, join.sh --solo) never runs it. While Uyuni HQ is fine it only reads: the minion's log, its saved copy of
# HQ's key, its lines, and a knock on HQ's door 4506 every 30 s (Salt's door speaks first, so the knock sends nothing).
# If HQ says no to this sandbox's key (the HQ table seats 8 crews), has not said yes after 10 minutes, or goes quiet
# (no Salt greeting 3 knocks in a row), it stops the minion and gives this sandbox YOUR OWN HQ (join.sh --solo CREW),
# with a short note in every terminal. It ends by itself when a newer join.sh runs, and after 2 hours.
# HQWATCH=0 in join.sh's environment: no watcher. The HQWATCH_* numbers are for the kit's tests.
set -u
ID=$1 IP=$2 CREW=$3; D=$(dirname "$0"); R=${SANDBOX_ROOT:-}; SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
MODE_FILE=${MODE_FILE:-$R/etc/osas26-mode}; LOG=${MINION_LOG:-/var/log/venv-salt-minion.log}
PKI=${MINION_PKI:-$R/etc/venv-salt-minion/pki/minion}; OUT=${HQWATCH_LOG:-/tmp/osas26-hqwatch.log}
TICK=${HQWATCH_TICK:-5} EVERY=${HQWATCH_EVERY:-30} KNOCKS=${HQWATCH_KNOCKS:-3} WAIT_S=${HQWATCH_ACCEPT_S:-600}
size(){ local n; n=$(wc -c < "$LOG" 2>/dev/null) || n=0; echo $((n + 0)); }
knock(){ timeout 8 bash -c "exec 3<>/dev/tcp/$IP/${HQWATCH_PORT:-4506} && head -c 1 <&3" 2>/dev/null | od -An -tx1 | grep -q ff; }
trusted(){ [ -s "$PKI/minion_master.pub" ] && ss -Htn state established '( dport = :4505 )' 2>/dev/null | grep -q .; }
say(){ local t; for t in ${HQWATCH_TTYS:-/dev/pts/[0-9]*}; do { echo; printf '\033[1;33m%s\033[0m\n' "$@"; } 2>/dev/null >>"$t"; done; }
t0=$(date +%s); off=$(size); knocked=0; dark=0; yes=""; why=""
while [ -z "$why" ]; do
  sleep "$TICK"; now=$(date +%s)
  [ "$(cat "$MODE_FILE" 2>/dev/null)" = hq ] && [ "$(cat "$R/etc/osas26-id" 2>/dev/null)" = "$ID" ] || exit 0   # a newer join.sh
  [ $((now - t0)) -lt "${HQWATCH_MAX_S:-7200}" ] || exit 0
  [ "$(size)" -ge "$off" ] || off=0                                                  # the log was rotated
  if tail -c +$((off + 1)) "$LOG" 2>/dev/null | grep -q "has rejected this minion's public key"; then
    why="said no to this sandbox's key (the HQ table seats 8 crews)"
  elif [ -z "$yes" ] && trusted; then yes=1
  elif [ -z "$yes" ] && [ $((now - t0)) -ge "$WAIT_S" ]; then
    why="has not said yes to this sandbox's key in $((WAIT_S / 60)) minutes"
  elif [ $((now - knocked)) -ge "$EVERY" ]; then
    knocked=$now; if knock; then dark=0; else dark=$((dark + 1)); fi
    [ "$dark" -lt "$KNOCKS" ] || why="went quiet: no answer on its Salt door, $KNOCKS knocks in a row"
  fi
done
say "[HQ table] Uyuni HQ $why." "No problem: this sandbox now gets YOUR OWN HQ, a real Salt master right here (a few seconds)."
if [ -d "$R/run/systemd/system" ]; then $SUDO systemctl stop venv-salt-minion 2>/dev/null; else $SUDO pkill -f venv-salt-minion 2>/dev/null; fi
if bash "$D/join.sh" --solo "$CREW" > "$OUT" 2>&1; then
  say "[YOUR HQ] Ready. Same Salt, same lessons, and you are its admin. Your next step: salt-key -a $(cat "$R/etc/osas26-id")" \
      "Then carry on with the steps for YOUR OWN HQ in this level. (What happened: cat $OUT)"
else say "[YOUR HQ] It did not start. Raise your HELP sticky: a helper runs /root/osas26/solo.sh status (and reads $OUT)"; fi
