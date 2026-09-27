#!/usr/bin/env bash
# join.sh [--solo|--hq] [nickname] — make THIS SANDBOX a Salt client (a minion) of an HQ: YOUR OWN HQ, a real Salt
# master inside this sandbox (solo.sh), or Uyuni HQ (the oSAS26 Uyuni server on the projector).
# NEVER run on your own computer: a Salt master can run any command as root on its minions.
# Which HQ: MODE in server.env decides. v7 pins MODE=solo: every sandbox runs its own HQ (same Salt, same lessons, and
# you are its admin). --solo / --hq here beats it for one sandbox (--hq: the HQ table, up to 8 crews on Uyuni).
# On Uyuni HQ, hqwatch.sh keeps an eye on the line: if HQ says no, has not said yes after 10 minutes, or goes quiet,
# it gives this sandbox its own HQ by itself (join.sh --solo), with a note in the terminal.
# With no MODE (auto): Uyuni HQ when it answers on door 4506 within HQ_WAIT seconds (6), else your own HQ.
# It prints its 4 steps, so it teaches as it runs. If the sandbox is linked to the game (crew.sh), it also tells the
# game which machine is yours; the game is never needed for joining.
set -euo pipefail
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
R=${SANDBOX_ROOT:-}                                   # "" on a sandbox; the kit's tests point it at a temp tree
MODE_FILE=${MODE_FILE:-$R/etc/osas26-mode}
# shellcheck source=solo.sh
. "$D/solo.sh"
if [ ! -f "$R/etc/osas26-sandbox" ]; then
  echo "STOP: run this only inside the workshop sandbox (Killercoda or Codespaces)."
  echo "Rule 1: only inside the sandbox. A Salt master has root on its minions. Never connect your own laptop to a server you don't control."; exit 1
fi
want=""; case "${1:-}" in --solo) want=solo; shift ;; --hq) want=hq; shift ;; esac
[ -x "$R/usr/bin/venv-salt-minion" ] || { echo "Salt bundle not ready yet - installing (up to 1 min)..."; $SUDO bash "$D/preinstall.sh"; }
linked=""; _game_load && linked=$GAME_CREW || true
nick="${1:-}"
if [ -z "$nick" ]; then
  echo "Use a nickname, not your full name: the screen may be photographed. The openSUSE Code of Conduct applies."
  if [ -n "$linked" ]; then read -rp "Your crew name [$linked]: " nick; nick=${nick:-$linked}
  else read -rp "Your crew name (2-12 characters, a-z 0-9): " nick; fi
fi
nick=$(printf '%s' "$nick" | tr 'A-Z' 'a-z'); [[ "$nick" =~ ^[a-z0-9]{2,12}$ ]] || { echo "Crew name: 2-12 characters, a-z 0-9 only"; exit 1; }
# server.env indirection: a rebuild onto a new IP is a git push; nothing on paper or slides hard-codes the FQDN
ENVF=$(game_server_env)
FQDN=$(sed -n 's/^FQDN=//p' "$ENVF"); IP=$(sed -n 's/^SERVER_IP=//p' "$ENVF"); KEY=$(sed -n 's/^KEY=//p' "$ENVF")
[ -n "$want" ] || case "$(sed -n 's/^MODE=//p' "$ENVF" | head -1 | tr -cd 'a-z')" in solo) want=solo ;; hq) want=hq ;; esac
if [ -z "$want" ]; then                               # auto: does Uyuni HQ answer on its Salt door?
  W=${HQ_WAIT:-6}
  if [[ $IP =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then   # (no address in server.env yet = no HQ to knock on)
    echo "Knocking on Uyuni HQ (door 4506, up to ${W} s)..."
    # Salt's door speaks first: ZeroMQ's greeting starts with the byte 0xff. So an open port with nothing alive behind
    # it (a relay whose HQ is gone) does not count as an answer; only a real Salt master does.
    timeout "$W" bash -c "exec 3<>/dev/tcp/${IP}/4506 && head -c 1 <&3" 2>/dev/null | od -An -tx1 | grep -q ff && want=hq
  fi
  [ -n "$want" ] || { want=solo; printf "\n  Uyuni HQ did not answer."; }
fi
old_fqdn=$(cat "$R/etc/osas26-fqdn" 2>/dev/null || true)
if [ "$want" = solo ]; then
  printf '\n  Today this sandbox runs YOUR OWN HQ: a real Salt master, right here.\n'
  printf '  Same Salt, same lessons, and you are its admin.\n\n'
  FQDN=$SOLO_FQDN; IP=127.0.0.1
  echo "[0/4] your own HQ: a Salt master in this sandbox (it listens on 127.0.0.1 only)"
  $SUDO bash "${SOLO_SH:-$D/solo.sh}" up || exit 1
elif solo_on; then                                     # back to Uyuni HQ: your own master can rest
  $SUDO bash "${SOLO_SH:-$D/solo.sh}" down || true
fi
ID="osas26-${nick}-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-3)"
echo "[1/4] name resolution: ${FQDN} -> ${IP}   (/etc/hosts: works even without DNS)"
grep -q " ${FQDN}\$" "$R/etc/hosts" || echo "${IP} ${FQDN}" | $SUDO tee -a "$R/etc/hosts" >/dev/null
echo "[2/4] fresh machine-id (Uyuni identifies systems by machine-id; cloned sandboxes share one)"
tr -d '-' <"$R/proc/sys/kernel/random/uuid" | $SUDO tee "$R/etc/machine-id" >/dev/null
echo "[3/4] the settings that make a minion (3 matter: master, id, activation_key):"
$SUDO install -d "$R/etc/venv-salt-minion/minion.d"
# log_level_logfile: info = the minion writes HQ's orders in its diary (the side quests read it)
$SUDO tee "$R/etc/venv-salt-minion/minion.d/osas26.conf" <<EOF
master: ${FQDN}
id: ${ID}
grains:
  susemanager:
    activation_key: "${KEY}"
server_id_use_crc: adler32
enable_legacy_startup_events: False
enable_fqdns_grains: False
log_level_logfile: info
EOF
# LD-1: once Uyuni has registered this machine it keeps its own copy (minion.d/susemanager.conf), and the file read
# last wins. So every master: line must name the HQ chosen now, or the minion keeps calling the old one.
for f in $(grep -l '^master:' "$R/etc/venv-salt-minion/minion.d/"*.conf 2>/dev/null); do $SUDO sed -i "s/^master: .*/master: ${FQDN}/" "$f"; done
# a NEW master (your own HQ, or back to Uyuni HQ) has a new key: the minion must forget the old one, or it refuses
# to talk ("The master key has changed")
if [ -n "$old_fqdn" ] && [ "$old_fqdn" != "$FQDN" ]; then $SUDO rm -f "$R/etc/venv-salt-minion/pki/minion/minion_master.pub"; fi
echo "[4/4] start the minion, check the Salt port"
if [ -d "$R/run/systemd/system" ]; then $SUDO systemctl enable --now venv-salt-minion >/dev/null 2>&1 || true; $SUDO systemctl restart venv-salt-minion
else $SUDO venv-salt-minion -d; fi                                     # Codespaces: no systemd PID 1
echo "$ID" | $SUDO tee "$R/etc/osas26-id" >/dev/null; echo "$FQDN" | $SUDO tee "$R/etc/osas26-fqdn" >/dev/null
echo "$want" | $SUDO tee "$MODE_FILE" >/dev/null
if timeout 5 bash -c "</dev/tcp/${FQDN}/4506" 2>/dev/null; then P="port 4506 reachable"; port=open
else P="port 4506 NOT reachable - raise your HELP sticky"; port=blocked; fi
if [ "$want" = solo ]; then
  printf '\n  ==========================================\n   YOUR SYSTEM:  %s\n   YOUR OWN HQ:  %s (this sandbox)\n   %s\n' "$ID" "$FQDN" "$P"
  printf '   Your master waits for YOUR yes: salt-key -a %s\n  ==========================================\n\n' "$ID"
  if game_post_sync l2.join "{\"minion_id\":\"$ID\",\"port4506\":\"$port\",\"hq\":\"solo\"}"; then
    printf '\033[1;36m[game] Crew %s is linked to %s. Your own HQ shows on the big screen as dotted lines.\033[0m\n\n' "$GAME_CREW" "$ID"
  fi
  game_detach bash "$D/probe.sh" solo --wait          # the moment YOU accept the key, the game hears it
  exit 0
fi
printf '\n  ==========================================\n   YOUR SYSTEM:  %s\n   %s\n   Now look at the projector.\n  ==========================================\n\n' "$ID" "$P"
if game_post_sync l2.join "{\"minion_id\":\"$ID\",\"port4506\":\"$port\"}"; then
  printf '\033[1;36m[game] Crew %s is linked to %s. Look at the big screen.\033[0m\n\n' "$GAME_CREW" "$ID"
fi
if [ "${HQWATCH:-1}" != 0 ]; then                    # the HQ table's safety net (never on your own HQ)
  game_detach bash "$D/hqwatch.sh" "$ID" "$IP" "$nick"
  echo "  If Uyuni HQ says no or goes quiet, this sandbox gets YOUR OWN HQ by itself, with a note right here."
fi
exit 0
