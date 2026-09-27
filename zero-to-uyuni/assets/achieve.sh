#!/usr/bin/env bash
# achieve.sh NAME "TEXT" (Geeko Corp skin of the research-v3 draft, ships in the Killercoda assets; called from verify scripts on success)
# 1) prints a banner into every terminal of THIS sandbox (root may write to /dev/pts/N)
# 2) tells the board via the Salt event bus (only works once the minion is joined and accepted)
# Never blocks the CHECK button for long: the event is sent in the background with a timeout.
set -u
name=${1:?name}; text=${2:-}
ACH=${ACH_DIR:-/etc/osas26}
[ -f "${SANDBOX_FLAG:-/etc/osas26-sandbox}" ] || exit 0
mark=$ACH/ach.$name
if [ ! -e "$mark" ]; then
  mkdir -p "$ACH" && touch "$mark"
  for t in /dev/pts/[0-9]*; do
    printf '\n\033[1;32m  ***  BADGE EARNED: %s  ***\033[0m\n  %s\n\n' "$name" "$text" 2>/dev/null > "$t"   # 2> first: no terminal open = no noise
  done
fi
if [ -s /etc/osas26-id ] && command -v venv-salt-call >/dev/null; then
  ( timeout 20 venv-salt-call --out=quiet event.send "osas26/ach/$name" >/dev/null 2>&1 & )
fi
exit 0
