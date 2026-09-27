#!/usr/bin/env bash
# 00-os-prep.sh (cp0) - PLAN §5.4 + FREE-GOLDEN §8.2: prepare the host, then load the host guard and the Salt-window
# timers BEFORE RKE2 exists. Two hosts, switched by /etc/os-release:
#   ubuntu2404  the plan (a lent VM, rung (d)): apt, AppArmor, ufw off, swap off, sshd on 22 + 2222 (ssh.socket)
#   leap16      only if a lender offers Leap 16.0: zypper, SELinux enforcing, firewalld off, NetworkManager conf
# Safe to re-run: the FQDN is chosen ONCE (lab.env), the guard is re-created, nothing is duplicated.
# Env: PUBLIC_IP=a.b.c.d  when the public IPv4 is NOT on the NIC (1:1 NAT clouds); the FQDN then uses it.
#      RUNNER=1  a GitHub-hosted runner (lab/runner/, .github/workflows/hq.yml): no inbound path exists except the
#                relay's tunnels, which arrive on the node's own address (never on the public interface), so the host
#                guard and the Salt-window timers are skipped (the window = the relay's lifetime); the 4 vCPU/16 GB
#                floor is a warning (a private repo's runner has 2 vCPU/8 GB, a public repo's 4 vCPU/16 GB).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
[ "$(id -u)" = 0 ] || die "run as root"
[ "$(uname -m)" = x86_64 ] || die "x86_64 only: the Helm tarball, the RKE2 image tarballs and the local-path/busybox digests are amd64 (README: multi-arch notes)"
OS=$(lab_os)
case $OS in ubuntu2404|leap16) ;; *) die "Ubuntu 24.04 or openSUSE Leap 16.0 only (this is ${OS#unsupported:})" ;; esac
cpus=$(nproc); memg=$(awk '/MemTotal/{print int($2/1048576)}' /proc/meminfo); freeg=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
RUNNER=${RUNNER:-0}
if [ "$cpus" -ge 4 ] && [ "$memg" -ge 15 ]; then :
elif [ "$RUNNER" = 1 ]; then echo "WARNING: $cpus vCPU, ${memg} GiB is below the lab floor (4 vCPU, 16 GB); RUNNER=1 builds anyway"
else die "need >= 4 vCPU and 16 GB RAM (found $cpus vCPU, ${memg} GiB) [K8S §4]"; fi
[ "$freeg" -ge 30 ] || die "need >= 30 GB free on / (found ${freeg} GB)"
install -d -m 0700 "$W"; cd "$W"; umask 077
t os_start
echo "host: $(. /etc/os-release; echo "$PRETTY_NAME") · kernel $(uname -r) · $cpus vCPU · ${memg} GiB · ${freeg} GB free"

# --- 1. the address and the name (chosen ONCE; renames are unsupported [K8S §6]) ---
route=$(ip -o -4 route get 1.1.1.1)
PUB_IF=$(sed -n 's/.* dev \([^ ]*\).*/\1/p' <<<"$route"); NIC_IP=$(sed -n 's/.* src \([^ ]*\).*/\1/p' <<<"$route")
[ -n "$PUB_IF" ] && [ -n "$NIC_IP" ] || die "no IPv4 default route"
if [ -s lab.env ] && grep -q '^FQDN=' lab.env; then
  FQDN=$(sed -n 's/^FQDN=//p' lab.env); PUB_IP=$(sed -n 's/^PUB_IP=//p' lab.env)
  echo "lab.env exists: keeping FQDN=$FQDN (chosen once)"
else
  PUB_IP=${PUBLIC_IP:-$NIC_IP}
  FQDN="uyuni.${PUB_IP//./-}.sslip.io"
fi
printf 'OS=%s\nPUB_IF=%s\nPUB_IP=%s\nSERVER_IP=%s\nFQDN=%s\nRUNNER=%s\n' "$OS" "$PUB_IF" "$PUB_IP" "$PUB_IP" "$FQDN" "$RUNNER" > lab.env
echo "public interface $PUB_IF · IPv4 $PUB_IP · FQDN $FQDN"

# --- 2. packages and the host's own firewall/MAC ---
if [ "$OS" = ubuntu2404 ]; then
  export DEBIAN_FRONTEND=noninteractive; APT="apt-get -o DPkg::Lock::Timeout=600 -qq"
  $APT update
  # iptables: hostPort needs it [RKE2 §2.2]; nftables: the guard; bind9-dnsutils: dig for check.sh; python3: the hooks
  $APT install -y git tmux jq gettext-base nftables iptables curl ca-certificates openssl python3 conntrack bind9-dnsutils >/dev/null
  if command -v ufw >/dev/null; then ufw disable >/dev/null 2>&1 || true; fi   # the guard is the only firewall
  swapoff -a; sed -i -E 's@^([^#].*[[:space:]]swap[[:space:]].*)$@# osas26: \1@' /etc/fstab
  echo "MAC: AppArmor $(aa-enabled 2>/dev/null || echo unknown) (the Uyuni server runs with superPrivileged: 30-uyuni.sh)"
else
  zypper -n ref
  zypper -n in iptables curl tar git-core jq openssl policycoreutils-python-utils envsubst tmux audit nftables   # names verified in the Leap 16.0 OSS filelists [R6]
  zypper -n in python3 bind-utils || echo "python3/bind-utils not installed (the hooks and check.sh's DNS line need them)"
  systemctl disable --now firewalld 2>/dev/null || true         # conflicts with Canal; the guard filters [RKE2 §2.2]
  echo "SELinux: $(getenforce)"; [ "$(getenforce)" = Enforcing ] || echo "WARNING: SELinux is not Enforcing"
fi
# Canal: NetworkManager must not manage the CNI interfaces (BEFORE RKE2) [RKE2 §2.2]
if systemctl is-active --quiet NetworkManager; then
  mkdir -p /etc/NetworkManager/conf.d
  cat >/etc/NetworkManager/conf.d/rke2-canal.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
  systemctl reload NetworkManager
else echo "NetworkManager not active (netplan/networkd or wicked): no CNI exclusion needed"; fi

# --- 3. nothing else may own the ports (a stray nginx or salt-master) [ASSETS §b #3, #8] ---
if ! systemctl is-active --quiet rke2-server; then
  if ss -H -lnt | awk '{print $4}' | grep -Eq ':(80|443|4505|4506|6443|9345)$'; then
    ss -lntp | grep -E ':(80|443|4505|4506|6443|9345)\b'; die "PORT-BUSY"; fi
fi

# --- 4. the name must resolve to this host from here AND from inside the pods (rehearsal F4) ---
for _ in 1 2 3 4 5; do got=$(getent ahostsv4 "$FQDN" | awk 'NR==1{print $1}'); [ "$got" = "$PUB_IP" ] && break; sleep 3; done
[ "$got" = "$PUB_IP" ] || die "$FQDN resolves to '${got:-nothing}', not $PUB_IP (sslip.io unreachable, or a resolver that drops private answers)"
echo "DNS: $FQDN -> $got"

# --- 5. clocks synced before any registration [BOOT §2.4] ---
for _ in $(seq 30); do [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && break; sleep 2; done
echo "NTPSynchronized=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"

# --- 6. sshd: key-only root, on 22 and 2222 (a carrier that filters 22) [FREE-GOLDEN §8.2] ---
# a drop-in named 00- wins: sshd keeps the FIRST value it reads (Ubuntu's 50-cloud-init.conf comes later)
install -d /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPort 22\nPort 2222\n' > /etc/ssh/sshd_config.d/00-osas26.conf
chmod 0644 /etc/ssh/sshd_config.d/00-osas26.conf
if [ "$OS" = leap16 ] && ! semanage port -l | grep -E '^ssh_port_t' | grep -qw 2222; then semanage port -a -t ssh_port_t -p tcp 2222; fi
# socket-activated sshd (Ubuntu 24.04) has no /run/sshd while no connection is open, and `sshd -t` needs it (a runner)
install -d -m 0755 /run/sshd
sshd -t
if systemctl is-enabled --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh.socket 2>/dev/null; then
  systemctl daemon-reload; systemctl restart ssh.socket          # Ubuntu 24.04: socket activation; the generator reads Port
elif systemctl is-active --quiet sshd; then systemctl reload sshd
else systemctl reload ssh; fi
# capture first: under pipefail, `sshd -T | grep -q` fails whenever grep exits early and sshd gets SIGPIPE
ST=$(sshd -T)
grep -qx 'passwordauthentication no' <<<"$ST" && grep -qx 'kbdinteractiveauthentication no' <<<"$ST" \
  && grep -qxE 'permitrootlogin (prohibit-password|without-password)' <<<"$ST" \
  || die 'sshd hardening NOT effective (an sshd_config without the Include line? put the lines at its top)'
for p in 22 2222; do for _ in $(seq 10); do ss -H -lnt "sport = :$p" | grep -q . && break; sleep 1; done
  ss -H -lnt "sport = :$p" | grep -q . || die "sshd is not listening on $p"; done
echo "sshd: key-only root on 22 and 2222"

# --- 7. the host guard + the Salt-window timers, BEFORE RKE2 (FREE-GOLDEN §6.5) ---
install -d -m 0755 /etc/osas26; touch /etc/osas26/lab-ok.list
if [ "$RUNNER" = 1 ]; then
  # A runner has no inbound connectivity at all; the relay's tunnels (lab/runner/relay.sh: 4505, 4506, 22 only) reach
  # the node from itself, so an iif-based guard would never see them, and dropping unknown traffic on the runner's NIC
  # could hit the platform's own probes. The Salt "window" is the relay's lifetime; 80/443 have no tunnel, ever.
  echo "RUNNER=1: no host guard, no Salt-window timers (inbound = the relay's tunnels only: lab/runner/relay.sh)"
  t os_done; exit 0
fi
sed "s/@PUB@/$PUB_IF/g" "$LAB/guard.nft" > /etc/osas26/guard.nft.new
nft -c -f /etc/osas26/guard.nft.new && mv /etc/osas26/guard.nft.new /etc/osas26/guard.nft
install -m 0755 "$LAB/salt-window.sh" /usr/local/sbin/osas26-salt-window
install -m 0644 "$LAB"/systemd/osas26-guard.service "$LAB"/systemd/osas26-salt-open.service "$LAB"/systemd/osas26-salt-open.timer \
                "$LAB"/systemd/osas26-salt-close.service "$LAB"/systemd/osas26-salt-close.timer /etc/systemd/system/
install -d /etc/systemd/system/rke2-server.service.d
install -m 0644 "$LAB/systemd/rke2-server-10-osas26-guard.conf" /etc/systemd/system/rke2-server.service.d/10-osas26-guard.conf
if command -v restorecon >/dev/null; then restorecon -v /usr/local/sbin/osas26-salt-window /etc/systemd/system/osas26-* >/dev/null; fi
systemctl daemon-reload
systemctl enable osas26-guard.service osas26-salt-open.timer osas26-salt-close.timer >/dev/null 2>&1
systemctl restart osas26-guard.service
systemctl start osas26-salt-open.timer osas26-salt-close.timer
/usr/local/sbin/osas26-salt-window status
t os_done
