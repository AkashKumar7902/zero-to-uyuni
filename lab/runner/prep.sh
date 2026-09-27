#!/usr/bin/env bash
# lab/runner/prep.sh CHECKOUT - RUNNER-HQ step 1 (as root on a GitHub-hosted ubuntu-24.04 runner, before build.sh):
#   - records the runner's facts (CPU, RAM, disk, swap, kernel, region) before and after;
#   - frees disk: removes preinstalled toolchains HQ never uses (Android, .NET, Haskell, Swift, CodeQL, browsers, ...);
#   - stops Docker and its containerd (RKE2 brings its own; this frees RAM and keeps Docker's rules out of the way);
#   - makes sure sshd exists (00-os-prep.sh makes it key-only on 22 + 2222) and installs the osas26 public key for root;
#   - copies the checkout to /root/zero-to-uyuni (the lab's fixed path, lib.sh).
# Nothing here is secret. Idempotent.
set -uo pipefail
SRC=${1:?usage: prep.sh CHECKOUT}
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
M=/root/osas26/runner; install -d -m 0700 /root/osas26 "$M"
facts(){
  echo "date:   $(date -u +%FT%TZ)"
  echo "kernel: $(uname -r)  $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "cpu:    $(nproc) x $(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)"
  free -m | sed 's/^/mem:    /'
  swapon --show --noheadings 2>/dev/null | sed 's/^/swap:   /'
  df -BG --output=target,size,used,avail / /mnt 2>/dev/null | sed 's/^/disk:   /'
  # the Azure region and VM size (instance metadata; no credentials involved)
  curl -s -m 3 -H Metadata:true 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' 2>/dev/null \
    | jq -r '"azure:  \(.location) \(.vmSize)"' 2>/dev/null || echo "azure:  (no metadata)"
}
facts > "$M/facts-before.txt"; cat "$M/facts-before.txt"
t0=$(date +%s)
# 1. disk: the big preinstalled toolchains (none is used by HQ; node and python stay). v7: a public repo's runner has
#    ~86 GB free on / already (measured 27 Sep, run 36329160782), so the removal (~2 min 50 s) runs only below 60 GB
free_g=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
if [ "${free_g:-0}" -ge "${PREP_DISK_OK_GB:-60}" ]; then echo "disk: ${free_g} GB free on /: no cleanup needed"; else
for d in /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL \
         /usr/share/swift /usr/local/share/powershell /usr/local/share/chromium /opt/microsoft /opt/google \
         /usr/lib/google-cloud-sdk /usr/share/miniconda /usr/local/julia* /opt/hostedtoolcache/PyPy \
         /opt/hostedtoolcache/go /opt/hostedtoolcache/Ruby /usr/local/aws-cli /usr/local/aws-sam-cli /usr/share/az_* /opt/az; do
  [ -e "$d" ] && rm -rf "$d" &
done
wait
fi
# 2. Docker: stopped (RKE2 has its own containerd); its images are removed to free disk
if systemctl is-active --quiet docker.service; then
  docker system prune -af >/dev/null 2>&1 || true
  systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
fi
echo "freed in $(( $(date +%s) - t0 )) s"
# 3. sshd (00-os-prep.sh hardens it) and the osas26 key for root (key-only: no password is ever set)
if ! command -v sshd >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -qq update && \
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -qq install -y openssh-server >/dev/null
fi
# key-only before the relay's ssh door opens (the same drop-in as 00-os-prep.sh step 6, which re-checks it)
install -d /etc/ssh/sshd_config.d; install -d -m 0755 /run/sshd
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPort 22\nPort 2222\n' > /etc/ssh/sshd_config.d/00-osas26.conf
sshd -t && { systemctl daemon-reload; systemctl restart ssh.socket 2>/dev/null || systemctl restart ssh; }
install -d -m 0700 /root/.ssh
grep -qxF -f "$SRC/lab/runner/osas26_ed25519.pub" /root/.ssh/authorized_keys 2>/dev/null \
  || cat "$SRC/lab/runner/osas26_ed25519.pub" >> /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
# 4. the lab's fixed path
rm -rf /root/zero-to-uyuni && cp -a "$SRC" /root/zero-to-uyuni && rm -rf /root/zero-to-uyuni/.git/hooks
facts > "$M/facts-after-prep.txt"; grep -E '^(disk|mem)' "$M/facts-after-prep.txt"
