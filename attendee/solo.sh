#!/usr/bin/env bash
# solo.sh up|down|status - YOUR OWN HQ: a real Salt master inside THIS sandbox. join.sh starts it when the room's HQ
# does not answer on door 4506 (or with MODE=solo in server.env, or join.sh --solo). Your minion talks to it on
# 127.0.0.1, and nothing outside this sandbox can reach it. You are its admin: you accept keys (salt-key -a), you
# send the orders (salt ... state.apply, salt ... cmd.run). Same Salt, same lessons as the room's HQ.
# SOURCE it for the helpers the other scripts use (solo_on, solo_accepted, solo_ping, SOLO_FQDN); RUN it for up/down.
#
# Where the master comes from (measured on 27 Sep 2026 in a clean Ubuntu 24.04 container; kit/test/solo-e2e.sh):
#  1. The Salt bundle this sandbox already has: venv-salt-minion 3006.0 from the Uyuni client tools (sha-pinned in
#     preinstall.sh). The Uyuni client-tools repo has no salt-master package (its 18 packages: venv-salt-minion,
#     spacecmd, mgradm/mgrctl/mgrpxy and exporters), but the bundle ships ALL of Salt 3006.0, the master included,
#     and every library the master needs. So: 0 bytes to download, about 1 s to start, and the master runs the same
#     Salt build as the minion. solo.sh adds only four small launchers (salt, salt-key, salt-master, salt-run).
#  2. Only if that master does not start: the Salt Project's official onedir packages, pinned to 3006.27 and
#     sha256-checked (the pins below match the GPG-signed Release -> Packages chain of packages.broadcom.com, key
#     10857FFDD3F91EAE577A21D664CBBC8173D76B3F). 27.1 MB to download, 231 MB on disk.
SOLO_FQDN=${SOLO_FQDN:-my-hq.osas26.test}           # your own HQ's name (.test never resolves outside, RFC 6761)
MODE_FILE=${MODE_FILE:-/etc/osas26-mode}             # join.sh writes it: "hq" (the room's HQ) or "solo" (your own)

solo_on() { [ "$(tr -cd 'a-z' 2>/dev/null < "$MODE_FILE")" = solo ]; }
SOLO_PKI=${SOLO_PKI:-/etc/salt/pki/master}           # your master's key folders: minions_pre/ (waiting), minions/ (yes)
# Did YOUR master accept this minion's key? Its own key folder says so (salt-key -a moves the key into minions/), so the
# waiters poll a file, not a Python process; without that folder (the kit's tests), salt-key is asked.
solo_accepted() {
  [ -n "${1:-}" ] || return 1
  [ -e "$SOLO_PKI/minions/$1" ] && return 0
  [ -d "$SOLO_PKI" ] && return 1
  timeout 20 "${SALT_KEY:-salt-key}" -l acc 2>/dev/null | grep -qx -- "$1"
}
# Does your master hear the minion? (test.ping: "are you there?", answered down the line the minion opened)
solo_ping() { [ -n "${1:-}" ] && timeout $((${2:-5} + 10)) "${SALT_CLI:-salt}" -t "${2:-5}" "$1" test.ping 2>/dev/null | grep -q True; }

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0            # sourced: the helpers only

set -uo pipefail
BUNDLE=${SOLO_BUNDLE:-/usr/lib/venv-salt-minion}
ONEDIR_VER=3006.27
ONEDIR_URL=https://packages.broadcom.com/artifactory/saltproject-deb/pool
ONEDIR_SHA_COMMON=d4b11095dd75471993589ab81389931e9d23d50c594ee4ce2ab132be179b39df
ONEDIR_SHA_MASTER=f492ec4202182b05884a4421a480db7da97d4632fbc6fa3c3576c3b93f6d52fe
CARD=/srv/salt/manager_org_1/osas26-welcome/init.sls # the path Uyuni gives the crew card, so every command matches
LAUNCHERS='salt:salt_main salt-key:salt_key salt-master:salt_master salt-run:salt_run'

listening() { timeout 2 bash -c '</dev/tcp/127.0.0.1/4506' 2>/dev/null; }
wait_up() { local _; for _ in $(seq "${1:-20}"); do listening && return 0; sleep 1; done; return 1; }
has_systemd() { [ -d /run/systemd/system ]; }

# HQ's crew card, byte for byte (kit/golden/crew-card.sls; kit/test/run-all.sh checks that the two never drift).
card_golden() { cat <<'SLS'
{#- Geeko Corp crew card = state channel osas26-welcome, file init.sls (replaces v1 welcome.sls + welcome-v2.sls).
    Salt renders this Jinja ON THE MINION, so every check reads a file that the attendee's own actions
    created in THEIR sandbox (catchup.sh 1 counts). No pillar dependency. Keep braces, percent signs and
    hash signs out of the art. Level 3 live edit = change ONLY the quoted text of "order"
    (paste:  find out what happened to the database.  - verify3.sh greps for it).
    LD-3 (brand + kindness): the art is an abstract salt crystal (no creature, no logo), and the card shows a
    SHIFT BADGE, never a rank: the badge is picked by the machine's own id (its hex tail), NEVER by the boxes, so
    no badge can mean "did less" (review fix, LD-3 delta). An empty box says how to fill it later, kindly. #}
{%- set order = "(waiting for orders from HQ...)" %}
{%- set fe = salt['file.file_exists'] %}
{%- set mid = grains['id'] %}
{%- set parts = mid.split('-') %}
{%- set nick = parts[1] if parts | length == 3 else mid %}
{%- set b_blueprint = fe('/root/uyuni.yaml') %}
{%- set b_crew = True %}
{%- set b_incident = fe('/root/.osas26-break') %}
{%- set b_evidence = fe('/root/.osas26-evidence') %}
{%- set badges = ['lamp keeper', 'salt miner', 'key keeper', 'line walker', 'cloud watcher'] %}
{%- set tail = parts[2] if parts | length == 3 else '0' %}
{%- set badge = badges[(tail | int(0, 16)) % 5] %}
{%- macro box(ok) %}{{ '[x]' if ok else '[ ]' }}{% endmacro %}
osas26_motd:
  file.managed:
    - name: /etc/motd
    - contents: |
        ============================================================
                   ______
                  /     /|          GEEKO CORP - SRE CREW CARD
                 /_____/ |          crew: {{ nick }}
                 |     | |          shift badge: {{ badge }}
                 |_____|/           (a salt crystal: HQ runs on Salt)
        ------------------------------------------------------------
         {{ box(b_blueprint) }} Blueprint   {{ "you read HQ's real Uyuni Helm chart" if b_blueprint else 'later: /root/osas26/catchup.sh 1 (it counts)' }}
         {{ box(b_crew) }} Onboarded   Uyuni manages this machine now
         {{ box(b_incident) }} Incident    /root/osas26/break.sh, then fix it
         {{ '[*]' if b_evidence else '[?]' }} Final case  {{ 'your evidence is sealed - verdict soon' if b_evidence else 'SEALED - verdict on the big screen' }}
        ------------------------------------------------------------
         ORDER FROM HQ: {{ order }}
        ------------------------------------------------------------
         {{ mid }} | Uyuni 2026.08 on RKE2 + openSUSE Leap 16
         openSUSE.Asia Summit 2026, Yogyakarta
osas26_card:
  file.managed:
    - name: /etc/osas26/card.txt
    - makedirs: True
    - contents: "{{ mid }} badge={{ badge }} blueprint={{ b_blueprint }} incident={{ b_incident }} evidence={{ b_evidence }}"
SLS
}
# Your own HQ's copy: a header for the reader, and two honest lines (your master manages it, not Uyuni).
card_solo() {
  printf '%s\n' "{#- YOUR OWN HQ's copy of HQ's crew card (solo.sh wrote it). Level 3: change the text of \"order\" below," \
                "    then apply it: salt \"\$(cat /etc/osas26-id)\" state.apply manager_org_1.osas26-welcome #}"
  card_golden | sed -e 's/Onboarded   Uyuni manages this machine now/Onboarded   your own HQ manages this machine now/' \
                    -e 's/| Uyuni 2026.08 on RKE2 + openSUSE Leap 16/| your own HQ: Salt 3006 in this sandbox/'
}

write_config() {
  install -d -m 0755 /etc/salt/master.d /srv/salt/manager_org_1/osas26-welcome /srv/pillar
  cat > /etc/salt/master.d/osas26-solo.conf <<'EOF'
# YOUR OWN HQ (oSAS26 solo.sh): a Salt master for this sandbox only.
interface: 127.0.0.1          # doors 4505/4506 open on this machine only: nobody outside can knock
auto_accept: False            # every new key waits for YOUR yes: salt-key -a <minion id>
worker_threads: 2             # one minion to serve: 2 workers, not 5 (less memory on a 2 GB sandbox)
file_roots:                   # recipes (states). The crew card: manager_org_1/osas26-welcome, where Uyuni keeps it
  base: [/srv/salt]
pillar_roots:                 # data your master gives your minion (pillar): org_id, as Uyuni gives it
  base: [/srv/pillar]
pki_dir: /etc/salt/pki/master
cachedir: /var/cache/salt/master
sock_dir: /var/run/salt/master
pidfile: /var/run/salt-master.pid
log_file: /var/log/salt/master
key_logfile: /var/log/salt/key
log_level_logfile: info
EOF
  [ -s "$CARD" ] || card_solo > "$CARD"             # never overwrite: your Level 3 edit survives a second join.sh
  printf "base:\n  '*':\n    - manager_org_1.osas26-welcome\n" > /srv/salt/top.sls
  printf "base:\n  '*':\n    - osas26\n" > /srv/pillar/top.sls
  printf '# pillar = data your own HQ gives your minion (Uyuni gives every machine its org_id too)\norg_id: 1\n' > /srv/pillar/osas26.sls
}

bundle_ok() { "$BUNDLE/bin/python" -c 'import salt.master, salt.key, salt.cli.salt, zmq' 2>/dev/null; }

launchers() {
  local c n f
  for c in $LAUNCHERS; do
    n=${c%%:*}; f=${c#*:}
    cat > "/usr/local/bin/$n" <<EOF
#!$BUNDLE/bin/python
# YOUR OWN HQ (oSAS26 solo.sh): Salt's own $n, run by the Salt 3006.0 bundle already on this sandbox.
import sys, warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from salt.scripts import $f
if __name__ == "__main__":
    sys.argv[1:1] = ["-c", "/etc/salt"]
    $f()
EOF
    chmod 0755 "/usr/local/bin/$n"
  done
}

start_bundle() {
  bundle_ok || { echo "      (the Salt bundle cannot run a master here)"; return 1; }
  launchers
  if has_systemd; then
    cat > /etc/systemd/system/salt-master.service <<'EOF'
[Unit]
Description=Your own HQ: a Salt master for this sandbox (oSAS26 solo.sh; Salt 3006.0 from venv-salt-minion)
After=network.target

[Service]
ExecStart=/usr/local/bin/salt-master
LimitNOFILE=100000
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now salt-master >/dev/null 2>&1
  else
    /usr/local/bin/salt-master -d                   # Codespaces: no systemd PID 1
  fi
  wait_up 20
}

start_onedir() {
  local APT="apt-get -o DPkg::Lock::Timeout=180"; export DEBIAN_FRONTEND=noninteractive
  echo "      downloading Salt $ONEDIR_VER (27 MB, official onedir packages, sha256-checked)..."
  curl -fsSL --max-time 180 -o /tmp/salt-common.deb "$ONEDIR_URL/salt-common_${ONEDIR_VER}_amd64.deb" \
    && curl -fsSL --max-time 60 -o /tmp/salt-master.deb "$ONEDIR_URL/salt-master_${ONEDIR_VER}_amd64.deb" \
    && printf '%s  %s\n' "$ONEDIR_SHA_COMMON" /tmp/salt-common.deb "$ONEDIR_SHA_MASTER" /tmp/salt-master.deb | sha256sum -c --quiet - \
    || { echo "      download or checksum failed"; return 1; }
  local c; for c in $LAUNCHERS; do rm -f "/usr/local/bin/${c%%:*}"; done   # ours would shadow Salt's own commands
  rm -f /etc/systemd/system/salt-master.service; has_systemd && systemctl daemon-reload
  $APT install -y -qq /tmp/salt-common.deb /tmp/salt-master.deb >/dev/null 2>&1 \
    || { $APT update -qq >/dev/null 2>&1 && $APT install -y -qq /tmp/salt-common.deb /tmp/salt-master.deb >/dev/null 2>&1; } || return 1
  if has_systemd; then systemctl enable salt-master >/dev/null 2>&1; systemctl restart salt-master; else salt-master -d; fi
  wait_up 30
}

up() {
  [ "$(id -u)" -eq 0 ] || { echo "solo.sh up needs root (the sandbox's terminal is root)."; return 1; }
  write_config
  if listening; then echo "      your own HQ is already running (a Salt master on 127.0.0.1)"; return 0; fi
  local how=${SOLO_MASTER:-bundle}
  if [ "$how" = bundle ] && start_bundle; then
    echo "      a Salt master started from the Salt bundle already here (0 MB downloaded)"
  elif start_onedir; then
    echo "      a Salt master started from the official Salt $ONEDIR_VER packages"
  else
    echo "      your own HQ did not start. Raise your HELP sticky: a helper runs /root/osas26/solo.sh status"; return 1
  fi
}

down() {
  if has_systemd; then systemctl disable --now salt-master >/dev/null 2>&1; fi
  pkill -f 'salt-master' 2>/dev/null
  return 0
}

status() {
  echo "mode: $(cat "$MODE_FILE" 2>/dev/null || echo 'not joined yet')"
  if listening; then echo "your own HQ: a Salt master listens on 127.0.0.1:4505/4506"; else echo "your own HQ: not running"; fi
  command -v salt-master >/dev/null && salt-master --version 2>/dev/null
  command -v salt-key >/dev/null && salt-key -L 2>/dev/null
  return 0
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  card) if [ "${2:-}" = golden ]; then card_golden; else card_solo; fi ;;   # for kit/test: the two cards
  *) echo "usage: /root/osas26/solo.sh up | down | status"; exit 1 ;;
esac
