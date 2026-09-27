#!/usr/bin/env bash
# catchup.sh 1|2|3|save - respawn at a checkpoint. Catching up earns the same boxes on the crew card, and the game
# counts it the same way (verify1.sh reports a catch-up blueprint as source "catchup").
D=$(dirname "$0")
case "${1:-}" in
  1) cp "$D/uyuni.yaml.prerendered" ~/uyuni.yaml && echo "Blueprint ready: ~/uyuni.yaml (Level 1 checkpoint). It counts." \
       && bash "$D/verify1.sh" >/dev/null 2>&1;;
  2) "$D/join.sh" "${2:-crew$((RANDOM%900+100))}";;
  3) "$D/join.sh" "${2:-crew$((RANDOM%900+100))}";;
  save) echo "Asking HQ for your crew card (up to 90 s)..."          # helper-only fallback: a minion-initiated highstate
        timeout 90 venv-salt-call state.apply --out=quiet >/dev/null 2>&1; cat /etc/motd;;
  *) echo "usage: /root/osas26/catchup.sh 1 | 2 [crew name] | 3 [crew name] | save";;
esac
