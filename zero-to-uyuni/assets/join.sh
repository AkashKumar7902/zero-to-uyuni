#!/usr/bin/env bash
# join.sh [nickname] — make THIS SANDBOX a Salt client (a minion) of the oSAS26 Uyuni server, HQ.
# NEVER run on your own computer: a Salt master can run any command as root on its minions.
# It prints its 4 steps, so it teaches as it runs. If the sandbox is linked to the game (crew.sh), it also tells the
# game which machine is yours; the game is never needed for joining.
set -euo pipefail
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
R=${SANDBOX_ROOT:-}                                   # "" on a sandbox; the kit's tests point it at a temp tree
if [ ! -f "$R/etc/osas26-sandbox" ]; then
  echo "STOP: run this only inside the workshop sandbox (Killercoda or Codespaces)."
  echo "Rule 1: only inside the sandbox. A Salt master has root on its minions. Never connect your own laptop to a server you don't control."; exit 1
fi
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
echo "[4/4] start the minion, check the Salt port"
if [ -d "$R/run/systemd/system" ]; then $SUDO systemctl enable --now venv-salt-minion >/dev/null 2>&1 || true; $SUDO systemctl restart venv-salt-minion
else $SUDO venv-salt-minion -d; fi                                     # Codespaces: no systemd PID 1
echo "$ID" | $SUDO tee "$R/etc/osas26-id" >/dev/null; echo "$FQDN" | $SUDO tee "$R/etc/osas26-fqdn" >/dev/null
if timeout 5 bash -c "</dev/tcp/${FQDN}/4506" 2>/dev/null; then P="port 4506 reachable"; port=open
else P="port 4506 NOT reachable - raise your HELP sticky"; port=blocked; fi
printf '\n  ==========================================\n   YOUR SYSTEM:  %s\n   %s\n   Now look at the projector.\n  ==========================================\n\n' "$ID" "$P"
if game_post_sync l2.join "{\"minion_id\":\"$ID\",\"port4506\":\"$port\"}"; then
  printf '\033[1;36m[game] Crew %s is linked to %s. Look at the big screen.\033[0m\n\n' "$GAME_CREW" "$ID"
fi
exit 0
