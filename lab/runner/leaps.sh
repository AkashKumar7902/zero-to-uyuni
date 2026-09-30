#!/usr/bin/env bash
# lab/runner/leaps.sh prep|register-a|bootstrap-b|accept-b|reset-b|status - RUNNER-HQ v7: Geeko Corp's two "office
# servers", leap-a and leap-b, as openSUSE Leap 16.0 systemd containers ON the HQ runner (podman, rootful, a bridge
# network). Run as root on HQ. The stage needs them for three moments: Meet HQ's System List and remote command on
# leap-a (pre-registered), and leap-b's LIVE bootstrap + the fingerprint vote (never registered before its cue).
#   prep          (in the background during the build) build the image (Leap 16.0 + systemd + sshd + venv-salt-minion
#                 from the Uyuni client tools), start leap-a and leap-b, each with its OWN fresh machine-id, then run
#                 clients/leap16-minion.sh in each (no registration). Waits for lab.env (HQ's FQDN) first.
#   register-a    (after HQ is up) HQ's golden key into both, `Host leap-a/leap-b` in /root/.ssh/config, then leap-a's
#                 official bootstrap (bootstrap-osas26.sh), its key accepted, and a wait until Uyuni lists leap-a
#   bootstrap-b   THE STAGE CUE (d-bootstrap-leapb; the Mac runs it with `door.sh leapb`): leap-b's official bootstrap,
#                 then its key fingerprint; the last two pairs are what the room compares at the vote
#   accept-b      the fallback of the UI's Accept (cue 13): salt-key -a leap-b
#   reset-b       leap-b back to "never registered" (clients/reset-leap-b.sh; rehearsals only)
#   status        both containers, their minion ids and machine-ids, HQ's keys and systems for leap-*
# /root/osas26/leaps.state holds one line for doors.env (mac/door.sh status shows it). Nothing here is secret.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib.sh"
IMG=localhost/osas26-leap16:latest; BASE=registry.opensuse.org/opensuse/leap:16.0
CT_REPO=https://download.opensuse.org/repositories/systemsmanagement:/Uyuni:/Stable:/openSUSE_Leap_16-Uyuni-Client-Tools/openSUSE_Leap_16.0/
ST=$W/leaps.state; LOG=$W/leaps.log
say(){ printf '%s %s\n' "$(date -u +%T)" "$*" | tee -a "$LOG" >&2; }
state(){ echo "$*" > "$ST"; say "state: $*"; }
kx(){ kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
cip(){ podman inspect -f '{{.NetworkSettings.IPAddress}}' "$1" 2>/dev/null; }
node_ip(){ sed -n 's/^NODE_IP=//p' /etc/osas26/relay.conf 2>/dev/null | head -1; }
[ "$(id -u)" = 0 ] || die "run as root"

prep(){
  local t0 e; t0=$(date +%s); state "preparing"
  for _ in $(seq 150); do [ -s "$W/lab.env" ] && break; sleep 2; done
  lab_env
  command -v podman >/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -qq update && \
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -qq install -y podman >/dev/null; }
  local B; B=$(mktemp -d)
  # shims: in a container, podman owns /etc/hostname (hostnamectl set-hostname to the SAME name is a no-op here) and
  # timedatectl may have no bus: leap16-minion.sh (the rehearsal-proven client script) runs unchanged. Leap 16.0 has no
  # uptime binary at all, and Meet HQ's 15:38 command is `whoami; uptime` @ leap-*: uptime = w's first line (30 Sep)
  cat > "$B/Containerfile" <<EOF
FROM $BASE
RUN zypper -n --gpg-auto-import-keys ref >/dev/null && \\
    zypper -n --gpg-auto-import-keys in --no-recommends systemd dbus-broker openssh-server openssh-clients \\
      curl iproute2 hostname gawk tar gzip util-linux ca-certificates procps >/dev/null && \\
    zypper -n ar -f $CT_REPO uyuni-client-tools && \\
    zypper -n --gpg-auto-import-keys in --no-recommends venv-salt-minion >/dev/null && \\
    zypper -n clean -a >/dev/null && systemctl enable sshd && : > /etc/machine-id && \\
    printf '#!/bin/sh\\n[ "\$1" = set-hostname ] && [ "\$2" = "\$(hostname)" ] && exit 0\\nexec /usr/bin/hostnamectl "\$@"\\n' > /usr/local/sbin/hostnamectl && \\
    printf '#!/bin/sh\\n/usr/bin/timedatectl "\$@" 2>/dev/null || date -u\\n' > /usr/local/sbin/timedatectl && \\
    printf '#!/bin/sh\\n# Leap 16.0 ships no uptime (procps 4): the same line is the first line of w\\nw | head -n 1\\n' > /usr/local/bin/uptime && \\
    chmod 0755 /usr/local/sbin/hostnamectl /usr/local/sbin/timedatectl /usr/local/bin/uptime
CMD ["/usr/lib/systemd/systemd"]
EOF
  say "podman $(podman --version | awk '{print $3}'): building the Leap 16.0 image"
  podman build -q -t "$IMG" "$B" >/dev/null 2>>"$LOG" || { state "FAILED (image build)"; rm -rf "$B"; return 1; }
  rm -rf "$B"; say "image built in $(( $(date +%s) - t0 )) s"
  for h in leap-a leap-b; do
    podman rm -f "$h" >/dev/null 2>&1
    # --no-hosts: the container's /etc/hosts is its own file (leap16-minion.sh edits it with sed -i)
    podman run -d --name "$h" --hostname "$h" --no-hosts --systemd=always "$IMG" >/dev/null 2>>"$LOG" \
      || { state "FAILED ($h did not start)"; return 1; }
  done
  for h in leap-a leap-b; do
    for _ in $(seq 60); do podman exec "$h" systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded' && break; sleep 1; done
    # a fresh machine-id of its own (written in place: podman may bind-mount the file), BEFORE leap16-minion.sh
    podman exec "$h" sh -c 'tr -d - </proc/sys/kernel/random/uuid > /etc/machine-id && touch /etc/osas26-mid-reset'
    e=$(podman exec -i "$h" bash -s -- "$h" "$FQDN" "$(node_ip)" < "$Z2U/clients/leap16-minion.sh" 2>&1) \
      || { printf '%s\n' "$e" >> "$LOG"; state "FAILED (leap16-minion.sh on $h)"; return 1; }
    printf '%s\n' "$e" | tail -n 2 >> "$LOG"
  done
  [ "$(podman exec leap-a cat /etc/machine-id)" != "$(podman exec leap-b cat /etc/machine-id)" ] || { state "FAILED (same machine-id)"; return 1; }
  state "prepared in $(( $(date +%s) - t0 )) s (leap-a $(cip leap-a), leap-b $(cip leap-b))"
}

ssh_setup(){
  local h ip
  [ -s /root/.ssh/id_ed25519.pub ] || die "HQ's golden key /root/.ssh/id_ed25519 is missing (40-harden.sh makes it)"
  install -d -m 0700 /root/.ssh; touch /root/.ssh/config; chmod 600 /root/.ssh/config
  for h in leap-a leap-b; do
    ip=$(cip "$h"); [ -n "$ip" ] || die "$h has no address (is it running? leaps.sh status)"
    podman exec -i "$h" sh -c 'install -d -m 0700 /root/.ssh; cat >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys' < /root/.ssh/id_ed25519.pub
    sed -i "/^# >>> $h (leaps.sh)/,/^# <<< $h/d" /root/.ssh/config
    printf '# >>> %s (leaps.sh)\nHost %s\n  HostName %s\n  User root\n  IdentityFile /root/.ssh/id_ed25519\n  StrictHostKeyChecking accept-new\n  ConnectTimeout 10\n# <<< %s\n' \
      "$h" "$h" "$ip" "$h" >> /root/.ssh/config
    ssh -n -o BatchMode=yes "$h" true || die "ssh $h failed"
  done
}

registered(){   # registered NAME: Uyuni lists the system (spacecmd, as reset-leap-b.sh reads it)
  ( . "$W/secrets.env"; kx spacecmd -y -u admin -p "$ADMIN_PASS" -- clear_caches >/dev/null 2>&1
    kx spacecmd -y -u admin -p "$ADMIN_PASS" -- system_list 2>/dev/null | tr '\r' '\n' | awk '{print $1}' | grep -qx "$1" )
}

register_a(){
  local t0 k; t0=$(date +%s); lab_env
  grep -q '^prepared' "$ST" 2>/dev/null || die "leaps are not prepared: $(cat "$ST" 2>/dev/null)"
  ssh_setup
  say "leap-a: the official bootstrap (bootstrap-osas26.sh, key 1-osas26-demo)"
  ssh -n -o BatchMode=yes leap-a "curl -Sks https://${FQDN}/pub/bootstrap/bootstrap-osas26.sh | bash" >> "$LOG" 2>&1 \
    || { state "FAILED (leap-a bootstrap)"; return 1; }
  for _ in $(seq 60); do kx salt-key -l pre --out=json 2>/dev/null | jq -e '.minions_pre | index("leap-a")' >/dev/null && break; sleep 2; done
  kx salt-key -y -a leap-a >/dev/null || { state "FAILED (leap-a key not pending)"; return 1; }
  for _ in $(seq 100); do registered leap-a && break; sleep 3; done
  registered leap-a || { state "FAILED (leap-a not registered after 5 min)"; return 1; }
  k=$(kx salt-key --out=json 2>/dev/null | jq -r '[.minions_pre[], .minions[]] | map(select(startswith("leap-b"))) | length')
  state "leap-a registered in $(( $(date +%s) - t0 )) s; leap-b clean (keys ${k:-?})"
}

bootstrap_b(){   # = the alias d-bootstrap-leapb, plus the fingerprint's last two pairs in big letters
  local out fp; lab_env
  out=$(ssh -n -o BatchMode=yes leap-b "curl -Sks https://${FQDN}/pub/bootstrap/bootstrap-osas26.sh | bash; venv-salt-call --local key.finger" 2>&1)
  printf '%s\n' "$out" | tail -n 25
  fp=$(printf '%s\n' "$out" | grep -oE '([0-9a-f]{2}:){31}[0-9a-f]{2}' | tail -1)
  [ -n "$fp" ] || { echo "no fingerprint in the output (see above)"; return 1; }
  echo; echo "leap-b's fingerprint ends in:   ${fp: -5}"
  echo "leap-b bootstrapped $(date -u +%T) UTC, fingerprint ends ${fp: -5}; waiting for the vote" > "$ST.b"
}

status(){
  echo "leaps.state: $(cat "$ST" 2>/dev/null || echo -)"; [ -s "$ST.b" ] && echo "leap-b: $(cat "$ST.b")"
  podman ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -E '^leap-[ab] ' || echo "no leap containers"
  for h in leap-a leap-b; do podman exec "$h" sh -c 'echo "'"$h"': hostname -f=$(hostname -f) machine-id=$(cut -c1-8 /etc/machine-id)... minion=$(systemctl is-active venv-salt-minion)"' 2>/dev/null; done
  kx salt-key --out=json 2>/dev/null | jq -r '"HQ keys: accepted \(.minions|map(select(startswith("leap")))) pending \(.minions_pre|map(select(startswith("leap"))))"'
}

case ${1:-} in
  prep) prep ;;
  register-a) register_a ;;
  bootstrap-b) bootstrap_b ;;
  accept-b) kx salt-key -y -a leap-b && echo "leap-b accepted (the UI shows it in Systems about a minute later)" ;;
  reset-b) rm -f "$ST.b"; bash "$Z2U/clients/reset-leap-b.sh" ;;
  status) status ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
