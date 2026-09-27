#!/usr/bin/env bash
# reset-leap-b.sh - return leap-b to "never registered" between rehearsals (PLAN §5.9 bullets; Uyuni clone-troubleshooting
# steps [BOOT §5.2 #18]). Run ON GOLDEN as root: it drives leap-b over ssh (Host leap-b in /root/.ssh/config).
# 1 stop the minion; 2 remove its pki, minion_id and minion.d/susemanager.conf; 3 a NEW machine-id (a fresh random one:
# `rm /etc/machine-id; systemd-machine-id-setup` on a running system writes the old id back, measured 2026-09-27);
# 4 on golden: delete system leap-b and its Salt key (also a stray "leap-b.<domain>" id from an unpinned hostname -f).
set -uo pipefail
. /root/osas26/secrets.env
kx(){ kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
ssh -n -o BatchMode=yes leap-b 'systemctl disable --now venv-salt-minion 2>/dev/null; rm -rf /etc/venv-salt-minion/pki /etc/venv-salt-minion/minion_id /etc/venv-salt-minion/minion.d/susemanager.conf; rm -f /etc/machine-id; tr -d - </proc/sys/kernel/random/uuid > /etc/machine-id; [ -d /var/lib/dbus ] && ln -sf /etc/machine-id /var/lib/dbus/machine-id; echo "leap-b: minion stopped, identity removed, new machine-id $(cut -c1-8 /etc/machine-id)..., hostname -f = $(hostname -f)"'
# spacecmd prints "name : id" lines (after a \r-overwritten cache banner) and caches the list inside the container: clear the cache, take the name column
kx spacecmd -y -u admin -p "$ADMIN_PASS" -- clear_caches >/dev/null 2>&1 || true
for id in $(kx spacecmd -y -u admin -p "$ADMIN_PASS" -- system_list 2>/dev/null | tr '\r' '\n' | awk '{print $1}' | grep -E '^leap-b([.]|$)'); do
  kx spacecmd -y -u admin -p "$ADMIN_PASS" -- system_delete -c FORCE_DELETE "$id" >/dev/null 2>&1
  # the removal is asynchronous (cleanup.sh's F7): wait until Uyuni no longer lists it, so the next step starts clean
  for _ in $(seq 30); do kx spacecmd -y -u admin -p "$ADMIN_PASS" -- clear_caches >/dev/null 2>&1
    kx spacecmd -y -u admin -p "$ADMIN_PASS" -- system_list 2>/dev/null | tr '\r' '\n' | awk '{print $1}' | grep -qx "$id" || break; sleep 2; done
  echo "system $id deleted"; done
for id in $(kx salt-key --out=json 2>/dev/null | jq -r '.[][]' | grep -E '^leap-b([.]|$)'); do kx salt-key -y -d "$id" >/dev/null && echo "key $id deleted"; done
kx spacecmd -y -u admin -p "$ADMIN_PASS" -- clear_caches >/dev/null 2>&1 || true
echo "leap-b reset: never registered"
