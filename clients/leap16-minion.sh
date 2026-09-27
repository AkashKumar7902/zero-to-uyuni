#!/usr/bin/env bash
# usage: leap16-minion.sh <hostname> <FQDN> <SERVER_IP> [register]
# PLAN §5.9, with the three fixes from the laptop dress rehearsal (2026-09-27):
#  R1 machine-id: `rm /etc/machine-id; systemd-machine-id-setup` on a RUNNING system prints "Reusing machine ID stored
#     in /run/machine-id" and writes the SAME id back (measured), so two leap machines cloned from one image would keep one id
#     and leap-b's registration would update leap-a. Write a fresh random id instead (as join.sh does).
#  R2 minion id: Uyuni's bootstrap script writes `hostname -f` into minion_id. With a DHCP search domain it is
#     "leap-b.<domain>" (measured: leap-b.akash.test), which the game (^leap-[ab]$), fleet-sync's fingerprint tail,
#     the UI accept "exactly by ID", reset-leap-b and the sim all miss. Make `hostname -f` = <hostname> and check it.
#  R3 exit status: the last line `[ "$4" = register ] && ...` returned 1 when not registering; now an if.
set -euo pipefail; H=$1 FQDN=$2 IP=$3
hostnamectl set-hostname "$H"
# leap-a and leap-b come from one image (v7: containers on the runner); never trust its machine-id, or leap-b's registration hits
# "Case 1.2 ... update the existing system" and overwrites leap-a on stage [L20].
[ -f /etc/osas26-mid-reset ] || { rm -f /etc/machine-id; tr -d '-' </proc/sys/kernel/random/uuid > /etc/machine-id
  [ -d /var/lib/dbus ] && ln -sf /etc/machine-id /var/lib/dbus/machine-id; touch /etc/osas26-mid-reset; }
# R2: the bootstrap registers `hostname -f` as the minion id: make it the short name (first /etc/hosts match wins)
if [ "$(hostname -f 2>/dev/null)" != "$H" ]; then sed -i "1i 127.0.1.1 $H" /etc/hosts; fi
[ "$(hostname -f)" = "$H" ] || { echo "hostname -f is '$(hostname -f)', not '$H': the bootstrap would use that as the minion id" >&2; exit 1; }
# same sshd policy as golden (§5.4)
install -d /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-osas26.conf
sshd -t && systemctl reload sshd
zypper -n ar -f https://download.opensuse.org/repositories/systemsmanagement:/Uyuni:/Stable:/openSUSE_Leap_16-Uyuni-Client-Tools/openSUSE_Leap_16.0/ uyuni-client-tools 2>/dev/null || true   # idempotent re-run
zypper -n --gpg-auto-import-keys in venv-salt-minion     # BEFORE registration, while distro repos are enabled [BOOT §1.1E]
grep -q " $FQDN\$" /etc/hosts || echo "$IP $FQDN" >> /etc/hosts
chronyc tracking || timedatectl                            # [BOOT §2.4]
echo "minion id at bootstrap will be: $(hostname -f)   machine-id: $(cut -c1-8 /etc/machine-id)..."
if [ "${4:-}" = register ]; then curl -Sks "https://$FQDN/pub/bootstrap/bootstrap-osas26.sh" | bash; fi   # skips install if present [BOOT §1.1A]
