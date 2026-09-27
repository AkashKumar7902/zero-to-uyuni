#!/usr/bin/env bash
# door.sh - the presenter Mac's door to RUNNER-HQ (the real Uyuni HQ on a GitHub-hosted runner; .github/workflows/hq.yml).
# Every hq run is a NEW HQ behind NEW doors, so nothing about HQ is written by hand: this script reads the run's newest
# "doors" artifact (public: names, ports, the SSH host PUBLIC key) with `gh`, and ssh reads that through ProxyCommand.
# No secret is ever written to a file: the admin password is fetched over SSH only when asked (door.sh pass/ui --check)
# and never printed. Lives in ~/osas26-kit/door/ (a copy of the repo's mac/door.sh; `mac/door.sh install` puts it there).
#
#   door.sh install            cloudflared from Homebrew (brew pin: no surprise upgrade), the ~/.ssh/config block
#                              (Host golden = the Cloudflare door, golden-bore = the bore.pub door), the state folder
#   door.sh status [RUN_ID]    the newest running hq run, its newest doors, HQ's state; probes both SSH doors
#   door.sh ssh [CMD...]       ssh to HQ as root: the Cloudflare door first, bore.pub if it does not answer
#   door.sh ui [--check|--open|--fg]   the Web UI tunnel 127.0.0.1:18443 -> HQ:443 (in the background, reconnecting),
#                              then the three Meet HQ tab URLs. --check: getVersion, login, the System List and the three
#                              tabs, timed. --open: a separate Chrome window that maps HQ's name to 127.0.0.1 (no root,
#                              no /etc/hosts) and trusts only this HQ's certificate key
#   door.sh pass               the admin password to the clipboard for 45 s (never printed)
#   door.sh leapb [accept|reset|status]   the live bootstrap of leap-b (cue 11) and its fingerprint's last two pairs;
#                              accept = the fallback of the UI's Accept (cue 13); reset = back to "never registered"
#   door.sh env                the HQ table's server.env as one paste-able command (for the speaker's own sandbox)
#   door.sh stop [hq]          stop this Mac's UI tunnel; `stop hq`: end the HQ run cleanly (asks first; logs upload)
#   door.sh proxy cf|bore      (ssh's ProxyCommand) connect to HQ's current door
# Env: REPO (default AkashKumar7902/zero-to-uyuni), DOOR_HOME (default ~/osas26-kit/door), SSH_KEY (~/.ssh/osas26_ed25519)
set -uo pipefail
REPO=${REPO:-AkashKumar7902/zero-to-uyuni}
DH=${DOOR_HOME:-$HOME/osas26-kit/door}; ST=$DH/state; DE=$ST/doors.env; KH=$ST/known_hosts
KEY=${SSH_KEY:-$HOME/.ssh/osas26_ed25519}; CF_WANT=2026.9.3
UIP=18443
TABS=(/rhn/manager/systems/list/all /rhn/manager/audit/cve /rhn/manager/systems/cmd)
TAB_NAMES=("Systems > System List > All" "Audit > CVE Audit" "Salt > Remote Commands")
die(){ printf 'door.sh: %s\n' "$*" >&2; exit 1; }
note(){ printf '  %s\n' "$*" >&2; }
d(){ sed -n "s/^$1=//p" "$DE" 2>/dev/null | head -1; }
cfbin(){ command -v cloudflared || { [ -x /opt/homebrew/bin/cloudflared ] && echo /opt/homebrew/bin/cloudflared; } || { [ -x /usr/local/bin/cloudflared ] && echo /usr/local/bin/cloudflared; }; }
need_gh(){ command -v gh >/dev/null || die "gh (GitHub CLI) is missing: brew install gh, then gh auth login"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in: gh auth login (any GitHub account can read this public repo's artifacts)"; }
need_doors(){ [ -s "$DE" ] || die "no doors yet: run  door.sh status  first (it finds the running hq run)"; }
age(){ local m; m=$(stat -f %m "$DE" 2>/dev/null || stat -c %Y "$DE"); echo $(( $(date +%s) - m )); }

install_kit(){
  local cf self
  mkdir -p "$DH" "$ST"; chmod 700 "$ST"
  self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  [ "$self" = "$DH/door.sh" ] || { cp "$self" "$DH/door.sh"; chmod 755 "$DH/door.sh"; echo "installed $DH/door.sh"; }
  if ! cf=$(cfbin); then
    command -v brew >/dev/null || die "cloudflared is missing and Homebrew is not installed"
    echo "brew install cloudflared"; brew install cloudflared || die "brew install cloudflared failed"; cf=$(cfbin)
  fi
  if command -v brew >/dev/null && brew list --versions cloudflared >/dev/null 2>&1; then
    brew pin cloudflared 2>/dev/null && echo "cloudflared pinned in Homebrew (brew upgrade leaves it; brew unpin cloudflared to allow)"
  fi
  v=$("$cf" --version 2>/dev/null | awk '{print $3}')
  [ "$v" = "$CF_WANT" ] && echo "cloudflared $v at $cf (the version HQ's side runs)" \
    || echo "cloudflared $v at $cf: HQ's side is pinned to $CF_WANT; any recent version can open 'access ssh'"
  [ -r "$KEY" ] || note "WARNING: the SSH key $KEY is missing (HQ accepts only the osas26 key)"
  touch "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
  awk '/^# >>> osas26 door kit/{s=1} !s{print} /^# <<< osas26 door kit/{s=0}' "$HOME/.ssh/config" > "$ST/ssh_config.new"
  cat >> "$ST/ssh_config.new" <<EOF
# >>> osas26 door kit (door.sh install) - no secrets: the doors are read from $DE
Host golden osas26-hq
  HostName osas26-hq
  ProxyCommand "$DH/door.sh" proxy cf
Host golden-bore osas26-hq-bore
  HostName osas26-hq
  ProxyCommand "$DH/door.sh" proxy bore
Host *.trycloudflare.com
  ProxyCommand $cf access ssh --hostname %h
Host golden osas26-hq golden-bore osas26-hq-bore *.trycloudflare.com
  User root
  IdentityFile $KEY
  IdentitiesOnly yes
  HostKeyAlias osas26-hq
  UserKnownHostsFile $KH
  StrictHostKeyChecking yes
  ServerAliveInterval 15
  ServerAliveCountMax 4
  ConnectTimeout 25
# <<< osas26 door kit
EOF
  cp "$HOME/.ssh/config" "$ST/ssh_config.bak"; mv "$ST/ssh_config.new" "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
  echo "$HOME/.ssh/config: Host golden (Cloudflare door) and golden-bore (bore.pub door); the old file is $ST/ssh_config.bak"
}

# the newest doors: the highest N of "doors-N" (the publisher's counter; artifact ids are NOT in upload order: measured
# 27 Sep, doors-2 got a smaller id than doors-1); "doors" (the first upload, N = 0) when no doors-N exists yet
latest_run(){   # prints "RUN_ID ARTIFACT" of the newest RUNNING hq run that published doors
  local runs id a
  runs=$(gh run list -R "$REPO" -w hq.yml -L 10 --json databaseId,status 2>/dev/null) || die "gh could not list the hq runs of $REPO"
  for id in $(jq -r '.[] | select(.status == "in_progress") | .databaseId' <<<"$runs"); do
    a=$(gh api "repos/$REPO/actions/runs/$id/artifacts?per_page=100" --jq \
        '[.artifacts[] | select((.name | test("^doors(-[0-9]+)?$")) and (.expired | not))] | max_by(.name | (capture("-(?<n>[0-9]+)$").n // "0") | tonumber) | .name // empty' 2>/dev/null)
    [ -n "$a" ] && { echo "$id $a"; return 0; }
  done
  return 1
}

fetch(){   # fetch [RUN_ID]: the newest doors artifact -> $DE, the host key -> $KH
  local run art T
  need_gh; mkdir -p "$ST"; chmod 700 "$ST"
  if [ -n "${1:-}" ]; then run=$1
    art=$(gh api "repos/$REPO/actions/runs/$run/artifacts?per_page=100" --jq \
          '[.artifacts[] | select((.name | test("^doors(-[0-9]+)?$")) and (.expired | not))] | max_by(.name | (capture("-(?<n>[0-9]+)$").n // "0") | tonumber) | .name // empty' 2>/dev/null)
    [ -n "$art" ] || die "run $run has no doors artifact (yet?): it appears ~1 min after the job starts"
  else
    read -r run art < <(latest_run) || {
      local last; last=$(gh run list -R "$REPO" -w hq.yml -L 1 --json databaseId,status,conclusion,createdAt --jq '.[0] | "\(.databaseId) \(.status) \(.conclusion // "-") \(.createdAt)"' 2>/dev/null)
      die "no hq run is running with doors (newest: ${last:-none}). Start one: GitHub app > Actions > hq > Run workflow, or gh workflow run hq.yml -R $REPO"; }
  fi
  T=$(mktemp -d); gh run download "$run" -R "$REPO" -n "$art" -D "$T" >/dev/null 2>&1 || { rm -rf "$T"; die "could not download $art of run $run"; }
  [ -s "$T/doors.env" ] || { rm -rf "$T"; die "$art has no doors.env"; }
  grep -q "^RUN_ID=$run\$" "$T/doors.env" || note "note: $art says RUN_ID=$(sed -n 's/^RUN_ID=//p' "$T/doors.env")"
  mv "$T/doors.env" "$DE"; rm -rf "$T"; echo "$art" > "$ST/artifact"
  local hk; hk=$(d SSH_HOSTKEY_PUB)
  [ -n "$hk" ] && echo "osas26-hq $hk" > "$KH"
}

probe_cf(){ local t0; t0=$(python3 -c 'import time;print(time.time())')
  ssh -o BatchMode=yes -o ConnectTimeout=25 golden 'cat /root/osas26/runner/state 2>/dev/null' 2>/dev/null \
    && python3 -c "import time;print('%.1f s' % (time.time()-$t0))"; }
probe_bore(){ local p; p=$(d BORE_SSH_PORT); [ -n "$p" ] || return 1
  python3 - "$(d BORE_SERVER)" "$p" <<'PY'
import socket, sys, time
t = time.time()
try:
    s = socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=8); s.settimeout(8); ok = s.recv(4) == b"SSH-"
except OSError:
    ok = False
print(f"banner in {time.time() - t:.1f} s" if ok else "no answer"); sys.exit(0 if ok else 1)
PY
}

status(){
  fetch "${1:-}"
  local run; run=$(d RUN_ID)
  echo "HQ run $run  https://github.com/$REPO/actions/runs/$run"
  echo "  state:      $(d HQ_STATE)   (doors from artifact $(cat "$ST/artifact"))"
  echo "  Cloudflare: $(d CF_SSH_HOST)   (names seen this run: $(d CF_NAMES_SEEN))"
  echo "  bore.pub:   $(d BORE_SERVER):$(d BORE_SSH_PORT)   HQ table Salt doors: $(d SALT_DOORS) CAP $(d CAP)"
  echo "  HQ:         $(d FQDN) (node $(d NODE_IP))   host key $(d SSH_HOSTKEY)"
  echo "  leaps:      $(d LEAPS)"
  printf '  door 1 (Cloudflare, ssh golden):   '; if [ -n "$(d CF_SSH_HOST)" ] && r=$(probe_cf); then echo "OK: $(tr '\n' ' ' <<<"$r")"; else echo "no answer"; fi
  printf '  door 2 (bore.pub, ssh golden-bore): '; probe_bore || true
  [ -s "$ST/ui.pid" ] && kill -0 "$(cat "$ST/ui.pid")" 2>/dev/null && echo "  UI tunnel: running on 127.0.0.1:$UIP (door.sh stop ends it)"
  return 0
}

pick(){   # pick: the first door that answers (golden, then golden-bore); refreshes the doors once if neither does
  local h try
  for try in 1 2; do
    for h in golden golden-bore; do
      [ "$h" = golden ] && [ -z "$(d CF_SSH_HOST)" ] && continue
      ssh -o BatchMode=yes -o ConnectTimeout=25 "$h" true 2>/dev/null && { echo "$h"; return 0; }
      note "$h did not answer"
    done
    [ "$try" = 1 ] && { note "refreshing the doors (a restarted door has a new name)"; fetch >/dev/null 2>&1 || true; }
  done
  return 1
}

sshx(){ need_doors; local h; h=$(pick) || die "neither door answers. door.sh status shows HQ's state; if HQ is gone: HQ-DARK (the twins)"
  note "via $h"; if [ $# -gt 0 ]; then exec ssh "$h" "$@"; else exec ssh -t "$h"; fi; }

ui_loop(){   # the tunnel, reconnecting; each round picks a door (a new Cloudflare name is picked up by a refresh)
  local h fails=0
  while :; do
    h=$(pick) || { fails=$((fails + 1)); sleep $(( fails < 6 ? 5 : 15 )); continue; }
    fails=0; printf '%s tunnel via %s\n' "$(date +%T)" "$h" >> "$ST/ui.log"
    ssh -N -o ExitOnForwardFailure=yes -o BatchMode=yes -L "127.0.0.1:$UIP:$(d NODE_IP):443" "$h" 2>>"$ST/ui.log"
    printf '%s tunnel dropped: reconnecting\n' "$(date +%T)" >> "$ST/ui.log"; sleep 2
  done
}

adminpass(){   # prints nothing; sets PW (from HQ over SSH)
  local h; h=$(pick) || die "no door answers"
  PW=$(ssh -o BatchMode=yes "$h" "sed -n 's/^ADMIN_PASS=//p' /root/osas26/secrets.env" 2>/dev/null)
  [ -n "$PW" ] || die "could not read the admin password from HQ (is the build done? door.sh status)"
}

ui(){
  need_doors; local f mode=${1:-} code cj; f=$(d FQDN)
  [ -n "$f" ] && [ -n "$(d NODE_IP)" ] || die "HQ's name is not known yet (state $(d HQ_STATE)): door.sh status again in a minute"
  [ "$mode" = --fg ] && { ui_loop; exit 0; }
  if ! { [ -s "$ST/ui.pid" ] && kill -0 "$(cat "$ST/ui.pid")" 2>/dev/null; }; then
    lsof -nP -iTCP:$UIP -sTCP:LISTEN >/dev/null 2>&1 && die "127.0.0.1:$UIP is taken by another program (lsof -nP -iTCP:$UIP)"
    nohup "$DH/door.sh" ui --fg >/dev/null 2>&1 & echo $! > "$ST/ui.pid"
  fi
  for _ in $(seq 60); do curl -sk -o /dev/null --max-time 5 --resolve "$f:$UIP:127.0.0.1" "https://$f:$UIP/" && break; sleep 1; done
  curl -sk -o /dev/null --max-time 5 --resolve "$f:$UIP:127.0.0.1" "https://$f:$UIP/" || die "the tunnel is not answering yet (see $ST/ui.log; door.sh status)"
  echo "Web UI tunnel: 127.0.0.1:$UIP -> HQ:443 (running in the background; door.sh stop ends it)"
  echo "Meet HQ tabs (in this order; log in as admin, the password: door.sh pass):"
  for i in 0 1 2; do printf '  %s. %-28s https://%s:%s%s\n' $((i + 1)) "${TAB_NAMES[$i]}" "$f" "$UIP" "${TABS[$i]}"; done
  echo "The browser must map $f to 127.0.0.1: door.sh ui --open does it (a separate Chrome window, no root)."
  if [ "$mode" = --check ]; then
    adminpass; cj=$(mktemp); chmod 600 "$cj"
    r(){ curl -sk -o /dev/null -w '%{http_code} %{time_total}' --max-time 30 --resolve "$f:$UIP:127.0.0.1" "$@"; }
    echo "check:"
    printf '  getVersion           %s s\n' "$(r "https://$f:$UIP/rhn/manager/api/api/getVersion")"
    code=$(printf '{"login":"admin","password":"%s"}' "$PW" | curl -sk -c "$cj" -o /dev/null -w '%{http_code} %{time_total}' --max-time 30 \
           --resolve "$f:$UIP:127.0.0.1" -H 'Content-Type: application/json' --data-binary @- "https://$f:$UIP/rhn/manager/api/auth/login")
    PW=""; printf '  login (API)          %s s\n' "$code"
    for i in 0 1 2; do printf '  %-20s %s s\n' "tab $((i + 1))" "$(r -b "$cj" "https://$f:$UIP${TABS[$i]}")"; done
    printf '  systems (API)        %s\n' "$(curl -sk -b "$cj" --max-time 30 --resolve "$f:$UIP:127.0.0.1" "https://$f:$UIP/rhn/manager/api/system/listSystems" | jq -r '[.result[].name] | sort | join(" ")' 2>/dev/null)"
    rm -f "$cj"
  fi
  if [ "$mode" = --open ]; then
    local spki
    spki=$(openssl s_client -connect "127.0.0.1:$UIP" -servername "$f" </dev/null 2>/dev/null | openssl x509 -pubkey -noout 2>/dev/null \
           | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary | base64)
    open -na "Google Chrome" --args --user-data-dir="$DH/chrome-meet-hq" --no-first-run \
      --host-resolver-rules="MAP $f 127.0.0.1" ${spki:+--ignore-certificate-errors-spki-list=$spki} \
      "https://$f:$UIP${TABS[0]}" "https://$f:$UIP${TABS[1]}" "https://$f:$UIP${TABS[2]}" \
      || die "could not open Google Chrome"
    echo "Chrome (profile $DH/chrome-meet-hq) opened with the three tabs; this HQ's certificate key is trusted in that window only"
  fi
}

pass(){ need_doors; adminpass; printf '%s' "$PW" | pbcopy; local h; h=$(printf '%s' "$PW" | shasum -a 256 | cut -c1-16); PW=""
  ( sleep 45; [ "$(pbpaste | shasum -a 256 | cut -c1-16)" = "$h" ] && pbcopy </dev/null ) >/dev/null 2>&1 &
  echo "the admin password is on the clipboard for 45 s (user: admin); paste it OFF the projector"; }

leapb(){ need_doors; local h; h=$(pick) || die "no door answers"
  case ${1:-bootstrap} in
    bootstrap) note "leap-b: the official bootstrap, live (≈ 30-60 s)"; ssh -t "$h" bash /root/zero-to-uyuni/lab/runner/leaps.sh bootstrap-b ;;
    accept) ssh "$h" bash /root/zero-to-uyuni/lab/runner/leaps.sh accept-b ;;
    reset) ssh "$h" bash /root/zero-to-uyuni/lab/runner/leaps.sh reset-b ;;
    status) ssh "$h" bash /root/zero-to-uyuni/lab/runner/leaps.sh status ;;
    *) die "leapb [bootstrap|accept|reset|status]" ;;
  esac; }

envline(){ need_doors; local h s; h=$(pick) || die "no door answers"
  s=$(ssh "$h" cat /root/osas26/server.env 2>/dev/null) || die "HQ has no server.env yet (the build is not done: door.sh status)"
  echo "# paste into the speaker's own sandbox (the HQ table), then: /root/osas26/join.sh --hq akash"
  printf "cat > /root/osas26/server.env <<'EOF'\n%s\nEOF\n" "$(grep -v '^#' <<<"$s")"; }

stop(){
  if [ "${1:-}" = hq ]; then
    need_doors; local run; run=$(d RUN_ID)
    if [ "${2:-}" != --yes ]; then read -rp "End HQ run $run now (the logs upload; the next start builds a NEW HQ)? Type STOP: " a; [ "$a" = STOP ] || die "not stopped"; fi
    local h; h=$(pick) || die "no door answers: cancel it instead: gh run cancel $run -R $REPO"
    ssh "$h" touch /root/osas26/runner/STOP && echo "STOP sent: the heartbeat ends within a minute, then the logs upload and run $run ends"
  fi
  if [ -s "$ST/ui.pid" ]; then local p; p=$(cat "$ST/ui.pid")
    pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; rm -f "$ST/ui.pid"; echo "UI tunnel stopped"
  else echo "no UI tunnel was running"; fi
}

proxy(){ need_doors
  case ${1:-} in
    cf) local h; h=$(d CF_SSH_HOST); [ -n "$h" ] || die "no Cloudflare door in $DE (door.sh status)"
        exec "$(cfbin)" access ssh --hostname "$h" ;;
    bore) local p; p=$(d BORE_SSH_PORT); [ -n "$p" ] || die "no bore.pub door in $DE"; exec nc "$(d BORE_SERVER)" "$p" ;;
    *) die "proxy cf|bore" ;;
  esac; }

case ${1:-} in
  install) install_kit ;;
  status) shift; status "$@" ;;
  ssh) shift; sshx "$@" ;;
  ui) shift; ui "$@" ;;
  pass) pass ;;
  leapb) shift; leapb "$@" ;;
  env) envline ;;
  stop) shift; stop "$@" ;;
  proxy) shift; proxy "$@" ;;
  refresh) fetch "${2:-}" && echo "doors: $(cat "$ST/artifact") ($(d HQ_STATE))" ;;
  *) sed -n '2,27p' "$0"; exit 2 ;;
esac
