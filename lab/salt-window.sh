#!/usr/bin/env bash
# salt-window.sh open [MIN] | close | status | reconcile | lab-add IP | lab-del IP
# Installed as /usr/local/sbin/osas26-salt-window (00-os-prep.sh, 40-harden.sh). FREE-GOLDEN §6.5 / §8.2.
#   open        4505/4506 reachable from anywhere (adds 0.0.0.0/0 to the guard's salt_ok set)
#   open MIN    the same, and a transient timer closes it again after MIN minutes (test windows close themselves)
#   close       4505/4506 unreachable again (flushes salt_ok) and cancels a pending auto-close
#   status      the guard, the window and the timers; exit 1 if the guard is missing
#   reconcile   the boot step (osas26-guard.service ExecStartPost): re-adds lab_ok from /etc/osas26/lab-ok.list, then
#               opens the window if now is inside the show window (Sat 3 Oct 2026, 13:25-17:30 WIB), else closes it
#   lab-add IP / lab-del IP   a separate demo VM (leap-a/leap-b) may reach 80/443/4505/4506; kept across reboots
# 80/443 are never opened by this script. Everything is logged to the journal (tag osas26-salt-window).
set -euo pipefail
T="inet osas26_guard"
START=${SALT_WINDOW_START:-2026-10-03 06:25:00 UTC}   # 13:25 WIB = the osas26-salt-open.timer
END=${SALT_WINDOW_END:-2026-10-03 10:30:00 UTC}       # 17:30 WIB = the osas26-salt-close.timer
LIST=/etc/osas26/lab-ok.list
# under systemd (the timers, the guard's ExecStartPost) stdout already goes to the journal: log once, not twice
log(){ echo "$*"; [ -n "${INVOCATION_ID:-}" ] || logger -t osas26-salt-window -- "$*" 2>/dev/null || true; }
guard(){ nft list table $T >/dev/null 2>&1; }
isopen(){ nft list set $T salt_ok 2>/dev/null | grep -q '0\.0\.0\.0/0'; }
ipok(){ [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || { echo "not an IPv4 address: $1" >&2; exit 2; }; }
# stopping only the TIMER is safe from inside the auto-close service itself (the timer has already fired)
cancel(){ systemctl stop osas26-salt-autoclose.timer >/dev/null 2>&1 || true
          systemctl reset-failed osas26-salt-autoclose.timer osas26-salt-autoclose.service >/dev/null 2>&1 || true; }
need(){ guard || { echo "the host guard (table $T) is NOT loaded: systemctl restart osas26-guard" >&2; exit 1; }; }
case "${1:-status}" in
  open)
    need
    isopen || nft add element $T salt_ok '{ 0.0.0.0/0 }'
    if [ -n "${2:-}" ]; then
      [[ $2 =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 600 ] || { echo "MIN must be 1-600" >&2; exit 2; }
      cancel
      systemd-run --quiet --collect --unit=osas26-salt-autoclose --on-active="${2}min" --timer-property=AccuracySec=1s \
        /usr/local/sbin/osas26-salt-window close
      log "Salt window OPEN for $2 min (auto-close at $(date -u -d "+$2 min" +%H:%M) UTC)"
    else
      log "Salt window OPEN (until 'osas26-salt-window close' or the osas26-salt-close timer)"
    fi ;;
  close)
    need; nft flush set $T salt_ok; cancel
    log "Salt window CLOSED" ;;
  reconcile)
    need
    if [ -s "$LIST" ]; then
      while read -r ip _; do case "$ip" in ''|'#'*) continue ;; esac; ipok "$ip"; nft add element $T lab_ok "{ $ip }"; done < "$LIST"
    fi
    now=$(date -u +%s); s=$(date -u -d "$START" +%s); e=$(date -u -d "$END" +%s)
    if [ "$now" -ge "$s" ] && [ "$now" -lt "$e" ]; then
      isopen || nft add element $T salt_ok '{ 0.0.0.0/0 }'; log "reconcile: inside the show window -> Salt window OPEN"
    else
      nft flush set $T salt_ok; log "reconcile: outside the show window -> Salt window CLOSED"
    fi ;;
  lab-add)
    need; ipok "${2:-}"; install -d -m 0755 /etc/osas26; touch "$LIST"
    grep -qxF "$2" "$LIST" || echo "$2" >> "$LIST"
    nft add element $T lab_ok "{ $2 }"; log "lab_ok + $2 (80/443/4505/4506 from this demo VM)" ;;
  lab-del)
    need; ipok "${2:-}"
    [ -f "$LIST" ] && { grep -vxF "$2" "$LIST" > "$LIST.new" || true; mv "$LIST.new" "$LIST"; }
    nft delete element $T lab_ok "{ $2 }" 2>/dev/null || true; log "lab_ok - $2" ;;
  status)
    if guard; then echo "guard:  present (table $T; public interface $(nft list chain $T pre | sed -n 's/.*iifname != "\([^"]*\)".*/\1/p' | head -1))"
    else echo "guard:  ABSENT (80/443 may be public!)"; exit 1; fi
    if isopen; then
      ac=""; if systemctl is-active --quiet osas26-salt-autoclose.timer; then
        ac=$(systemctl list-timers --no-pager osas26-salt-autoclose.timer 2>/dev/null | awk 'NR==2 {print $1" "$2" "$3" "$4}'); fi
      echo "window: OPEN${ac:+ (auto-close $ac)}"
    else echo "window: CLOSED"; fi
    echo "lab_ok: $(nft list set $T lab_ok 2>/dev/null | sed -n 's/.*elements = { \(.*\) }.*/\1/p')"
    systemctl list-timers --all --no-pager 'osas26-salt-*' 2>/dev/null | sed -n '1,4p' ;;
  *) echo "usage: osas26-salt-window open [MIN] | close | status | reconcile | lab-add IP | lab-del IP" >&2; exit 2 ;;
esac
