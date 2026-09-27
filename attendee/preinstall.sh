#!/usr/bin/env bash
# preinstall.sh - the Killercoda intro "background" (and the Codespaces postCreateCommand): helm, the Salt bundle, `why`.
# PLAN §5.9, unchanged. join.sh runs it again if the Salt bundle is still missing.
set -euo pipefail
touch /etc/osas26-sandbox                                          # the ONLY thing join.sh trusts [HOM §2.5]
trap 'touch /tmp/osas26-ready' EXIT                                # v3 review: wait.sh never hangs, even if a download fails
grep -q 'osas26' /root/.bashrc 2>/dev/null || echo 'export PATH=$PATH:/root/osas26; cd /root/osas26 2>/dev/null' >> /root/.bashrc   # new tabs
REPO="https://download.opensuse.org/repositories/systemsmanagement:/Uyuni:/Stable:/Ubuntu2404-Uyuni-Client-Tools/xUbuntu_24.04/"
if ! command -v helm >/dev/null; then
  curl -fsSLo /tmp/helm.tgz https://get.helm.sh/helm-v4.2.4-linux-amd64.tar.gz
  echo "c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3  /tmp/helm.tgz" | sha256sum -c -
  tar -xzf /tmp/helm.tgz -C /tmp && install -m0755 /tmp/linux-amd64/helm /usr/local/bin/helm
fi
REL="https://github.com/AkashKumar7902/zero-to-uyuni/releases/download/deb-2026-09"   # release asset (§5.0): GitHub CDN, sha-pinned
APT="apt-get -o DPkg::Lock::Timeout=180"; export DEBIAN_FRONTEND=noninteractive
if [ ! -x /usr/bin/venv-salt-minion ]; then
  if curl -fsSL --max-time 90 -o /tmp/vsm.deb "$REL/venv-salt-minion_amd64.deb" \
     && curl -fsSL --max-time 20 "$REL/venv-salt-minion_amd64.deb.sha256" | awk '{print $1"  /tmp/vsm.deb"}' | sha256sum -c --quiet -; then
    $APT install -y -qq /tmp/vsm.deb || { $APT update -qq && $APT install -y -qq /tmp/vsm.deb; }   # Depends: gnupg, logrotate, systemd [feasibility review, OBS metadata]
  else                                                                # fallback: the OBS apt repo (a live third-party dependency)
    install -d -m0755 /etc/apt/keyrings
    curl -fsSL "${REPO}Release.key" | gpg --dearmor --yes -o /etc/apt/keyrings/uyuni-client-tools.gpg     # Release.key 200 [HOM V11]
    echo "deb [signed-by=/etc/apt/keyrings/uyuni-client-tools.gpg] ${REPO} /" > /etc/apt/sources.list.d/uyuni-client-tools.list
    $APT update -qq && $APT install -y -qq venv-salt-minion         # 28.6 MB [HOM V11]
  fi
  systemctl disable --now venv-salt-minion 2>/dev/null || true    # ⚠️ deb postinst may auto-start it with master "salt"
fi
# v3: `why` prints the reason the last CHECK failed (the verify scripts write it to /root/.check) [FUN §1.2, M]
printf '#!/bin/sh\ncat /root/.check 2>/dev/null || echo "No CHECK message yet."\n' > /usr/local/bin/why && chmod +x /usr/local/bin/why
touch /tmp/osas26-ready
