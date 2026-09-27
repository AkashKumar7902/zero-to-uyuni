#!/usr/bin/env bash
# lab/runner/relay-cf.sh - RUNNER-HQ's second relay: Cloudflare quick tunnels (trycloudflare.com: no account, no card).
# Why it exists: bore.pub resets EVERY connection of a client IP that holds more than 64 connections to its control
# port 7835 (measured 27 Sep, RUNNER-HQ-REPORT.md §5), and a bore client opens one such connection per tunnelled TCP
# connection. A minion holds 2, and 2-4 during a job, so ~12-25 minions is bore.pub's ceiling for one HQ. cloudflared
# multiplexes every tunnelled connection over a few QUIC connections to Cloudflare's edge: HQ's own connection count
# does not grow with the fleet (31 minions measured: registration, highstate, remote command, a full outage storm).
# The price: every sandbox runs its own forwarder (`cloudflared access tcp`: lab/loadtest/cf-doors.sh, the proposed kit
# change D-K3), and a quick tunnel's NAME changes whenever its cloudflared process restarts (server.env changes then;
# cf-doors.sh follows it). Installed as /usr/local/sbin/osas26-relay-cf.
#   relay-cf.sh install            cloudflared 2026.9.3 (linux-amd64), sha256-pinned, into /usr/local/bin
#   relay-cf.sh up salt|ssh|all    start the supervised quick tunnels + the watchdog, wait for their names, write
#                                  /root/osas26/cf.env (names only: nothing secret)
#   relay-cf.sh status             names, edge locations, name changes, the last end-to-end probe of each door
#   relay-cf.sh down [door]
#   relay-cf.sh run DOOR           (systemd) one quick tunnel; records its name; a new name is logged as NAME CHANGED
#   relay-cf.sh watch              (systemd) end-to-end probes every 30 s through local `cloudflared access` forwarders;
#                                  v7: a door dead for 5 min is restarted (a new name; doors.sh republishes it)
# v7: the presenter's SSH door (cf-ssh) runs on EVERY relay (hq.yml ssh_cf=on); cf-pub/cf-req stay test tooling.
# THE ONLY DOORS (an allow-list: a web port can never be tunnelled):
#   cf-pub  -> <node IP>:4505 (Traefik's hostPort -> Salt publish)    cf-req -> <node IP>:4506 (Salt request/auth)
#   cf-ssh  -> 127.0.0.1:22   (sshd, key-only; client: ssh -o ProxyCommand='cloudflared access ssh --hostname %h')
# Quick-tunnel terms (developers.cloudflare.com, "Quick Tunnels"): "intended for testing and development only", a hard
# limit of 200 in-flight requests per tunnel (one tunnelled TCP connection = one), no SLA.
set -uo pipefail
CF_V=2026.9.3
CF_SHA=77e26d8d900e0b8469f416239d14b5f296525fdf79fee6f511ef55609e3fbac2   # cloudflared-linux-amd64 (GitHub asset digest)
CONF=/etc/osas26/relay.conf; RUN=/run/osas26-cf; W=/root/osas26
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"
die(){ echo "relay-cf: $*" >&2; exit 1; }
ev(){ install -d -m 0755 "$RUN"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$RUN/events.log" >&2; }
node_ip(){ [ -n "${NODE_IP:-}" ] && { echo "$NODE_IP"; return; }; ip -o -4 route get 1.1.1.1 | sed -n 's/.* src \([^ ]*\).*/\1/p'; }
door(){   # door NAME -> "origin-url local-probe-port probe-kind"
  case $1 in
    cf-pub) echo "tcp://$(node_ip):4505 24505 zmtp" ;;
    cf-req) echo "tcp://$(node_ip):4506 24506 zmtp" ;;
    cf-ssh) echo "tcp://127.0.0.1:22 24022 ssh" ;;
    *) die "unknown door '$1' (only cf-pub, cf-req, cf-ssh: web ports are never tunnelled)" ;;
  esac; }

run(){
  local name=$1 url pid h="" old
  read -r url _ _ <<<"$(door "$name")"; install -d -m 0755 "$RUN"
  [ -f "$RUN/$name.log" ] && mv -f "$RUN/$name.log" "$RUN/$name.log.prev"
  cloudflared tunnel --no-autoupdate --logfile "$RUN/$name.log" --url "$url" >/dev/null 2>&1 & pid=$!
  for _ in $(seq 60); do
    h=$(grep -oE '[a-z0-9-]+\.trycloudflare\.com' "$RUN/$name.log" 2>/dev/null | grep -v '^api\.' | head -1 || true)
    [ -n "$h" ] && break; kill -0 "$pid" 2>/dev/null || break; sleep 1
  done
  old=$(cat "$RUN/$name.host" 2>/dev/null || true)
  if [ -n "$h" ]; then
    echo "$h" > "$RUN/$name.host.new" && mv "$RUN/$name.host.new" "$RUN/$name.host"
    if [ -n "$old" ] && [ "$old" != "$h" ]; then ev "$name: NAME CHANGED $old -> $h (server.env must carry it: relay-cf.sh up rewrites cf.env)"
    else ev "$name: UP $h -> $url"; fi
    write_env
  else ev "$name: no quick-tunnel name within 60 s (see $RUN/$name.log)"; fi
  wait "$pid"; ev "$name: cloudflared exited ($?): systemd restarts it (a NEW name)"
}

probe_raw(){ python3 - "$@" <<'PY'
import socket, sys, time
port, kind = int(sys.argv[1]), sys.argv[2]
t = time.monotonic()
try:
    s = socket.create_connection(('127.0.0.1', port), timeout=10); s.settimeout(10)
    if kind == 'zmtp':
        s.sendall(b'\xff' + b'\x00' * 8 + b'\x7f'); ok = s.recv(1) == b'\xff'
    else:
        ok = s.recv(4) == b'SSH-'
    s.close()
except OSError:
    ok = False
if not ok: sys.exit(1)
print(f"{(time.monotonic() - t) * 1000:.0f}")
PY
}

watch(){   # one local `cloudflared access tcp` forwarder per door, re-pointed when a name changes; probe every 30 s.
  # v7: a door that fails end to end for CF_RESTART_FAILS probes in a row (default 10 = 5 min: cloudflared's own edge
  # reconnects take seconds) is restarted: a NEW name, which run() records, cf.env carries and doors.sh publishes
  declare -A fwd=() at=() nf=()
  while :; do
    for name in cf-pub cf-req cf-ssh; do
      [ -s "$RUN/$name.host" ] || continue
      read -r _ lp kind <<<"$(door "$name")"; h=$(cat "$RUN/$name.host")
      if [ "${at[$name]:-}" != "$h" ] || ! kill -0 "${fwd[$name]:-0}" 2>/dev/null; then
        [ -n "${fwd[$name]:-}" ] && kill "${fwd[$name]}" 2>/dev/null
        cloudflared access tcp --hostname "$h" --url "127.0.0.1:$lp" >/dev/null 2>&1 & fwd[$name]=$!; at[$name]=$h; nf[$name]=0; sleep 2
      fi
      if ms=$(probe_raw "$lp" "$kind"); then printf 'ok %s ms at %s\n' "$ms" "$(date -u +%T)" > "$RUN/$name.probe"; nf[$name]=0
      else
        nf[$name]=$(( ${nf[$name]:-0} + 1 )); printf 'FAIL x%s at %s\n' "${nf[$name]}" "$(date -u +%T)" > "$RUN/$name.probe"
        if [ "${nf[$name]}" -ge "${CF_RESTART_FAILS:-10}" ]; then
          ev "$name: ${nf[$name]} probes failed end to end: restarting its quick tunnel (a NEW name follows)"
          systemctl restart "osas26-cf@$name.service"; nf[$name]=0; sleep 5
        fi
      fi
    done
    sleep "${WATCH_EVERY:-30}"
  done
}

write_env(){
  umask 022
  { echo "# cf.env - RUNNER-HQ's Cloudflare quick-tunnel doors (not secret). Written by lab/runner/relay-cf.sh at $(date -u +%FT%TZ)."
    echo "CF_PUB_HOST=$(cat "$RUN/cf-pub.host" 2>/dev/null)"; echo "CF_REQ_HOST=$(cat "$RUN/cf-req.host" 2>/dev/null)"
    echo "CF_SSH_HOST=$(cat "$RUN/cf-ssh.host" 2>/dev/null)"; } > "$W/cf.env.new" && mv "$W/cf.env.new" "$W/cf.env"
}

up(){
  local want=() d ok=1 end
  case ${1:-all} in ssh) want=(cf-ssh) ;; salt) want=(cf-pub cf-req) ;; all) want=(cf-pub cf-req cf-ssh) ;; *) die "up ssh|salt|all" ;; esac
  command -v cloudflared >/dev/null || install_cf
  install -d -m 0755 "$RUN"; install -d -m 0700 "$W"
  install -m 0755 "$(readlink -f "$0")" /usr/local/sbin/osas26-relay-cf
  cat > /etc/systemd/system/osas26-cf@.service <<'EOF'
[Unit]
Description=oSAS26 RUNNER-HQ Cloudflare quick tunnel %i (supervised)
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/local/sbin/osas26-relay-cf run %i
KillMode=control-group
Restart=always
RestartSec=3
EOF
  cat > /etc/systemd/system/osas26-cf-watch.service <<'EOF'
[Unit]
Description=oSAS26 RUNNER-HQ Cloudflare quick-tunnel watchdog (end-to-end probes)
[Service]
Type=simple
ExecStart=/usr/local/sbin/osas26-relay-cf watch
KillMode=control-group
Restart=always
RestartSec=5
EOF
  systemctl daemon-reload
  for d in "${want[@]}"; do systemctl start "osas26-cf@$d.service"; done
  systemctl start osas26-cf-watch.service
  end=$(( $(date +%s) + ${UP_WAIT:-120} ))
  for d in "${want[@]}"; do
    until [ -s "$RUN/$d.probe" ] && grep -q '^ok' "$RUN/$d.probe"; do
      [ "$(date +%s)" -lt "$end" ] || { ev "$d: NOT UP after ${UP_WAIT:-120} s"; ok=0; break; }; sleep 2; done
    ev "$d: $(cat "$RUN/$d.host" 2>/dev/null) (probe $(cat "$RUN/$d.probe" 2>/dev/null))"
  done
  write_env; [ "$ok" = 1 ]
}

status(){
  [ -s "$W/cf.env" ] && grep -v '^#' "$W/cf.env"
  for d in cf-pub cf-req cf-ssh; do
    printf '%-7s %-8s %-52s edge %-8s probe %-24s names %s\n' "$d" "$(systemctl is-active "osas26-cf@$d.service" 2>/dev/null)" \
      "$(cat "$RUN/$d.host" 2>/dev/null || echo -)" \
      "$(grep -ho 'location[^a-z]*[a-z]*[0-9]*' "$RUN/$d.log" 2>/dev/null | tail -1 | grep -oE '[a-z]+[0-9]+$' || echo -)" \
      "$(cat "$RUN/$d.probe" 2>/dev/null || echo -)" "$(grep -c "$d: \(UP\|NAME CHANGED\)" "$RUN/events.log" 2>/dev/null || true)"
  done
}

down(){ if [ -n "${1:-}" ]; then systemctl stop "osas26-cf@$1.service"
        else systemctl stop osas26-cf-watch.service 'osas26-cf@*.service' 2>/dev/null; fi; }

install_cf(){
  local T; T=$(mktemp)
  curl -fsSL --retry 3 -o "$T" "https://github.com/cloudflare/cloudflared/releases/download/$CF_V/cloudflared-linux-amd64"
  echo "$CF_SHA  $T" | sha256sum -c --quiet - || { rm -f "$T"; die "cloudflared $CF_V checksum MISMATCH: not installed"; }
  install -m 0755 "$T" /usr/local/bin/cloudflared; rm -f "$T"; cloudflared --version
}

case ${1:-} in
  install) install_cf ;;
  up) [ "$(id -u)" = 0 ] || die "run as root"; up "${2:-all}" ;;
  status) status ;;
  down) down "${2:-}" ;;
  run) run "${2:?door}" ;;
  watch) watch ;;
  *) sed -n '2,25p' "$0"; exit 2 ;;
esac
