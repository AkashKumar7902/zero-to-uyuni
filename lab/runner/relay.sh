#!/usr/bin/env bash
# lab/runner/relay.sh - RUNNER-HQ: HQ's doors on a public TCP relay that needs no account (bore.pub, bore v0.6.0).
# A GitHub-hosted runner accepts no inbound connection; the bore client dials OUT to the relay, which then listens on a
# public port and hands every connection back through the client. Installed as /usr/local/sbin/osas26-relay.
#   relay.sh install            download bore v0.6.0 (x86_64 musl), check the pinned sha256, install /usr/local/bin/bore
#   relay.sh up ssh|salt|all    start the supervised doors (systemd osas26-relay@<door> + the watchdog), wait for their
#                               remote ports, write /root/osas26/relay.env (endpoints only: nothing secret)
#   relay.sh status             endpoints, the last end-to-end probe of each door, restarts
#   relay.sh down [door]        stop a door (or all of them and the watchdog)
#   relay.sh tunnel DOOR        (systemd) the client loop of one door: sticky remote port, backoff, busy-port handling
#   relay.sh watch              (systemd) the watchdog: probes every door end to end, kills a client that stopped working
#   relay.sh probe DOOR         one end-to-end probe from here, through the relay and back (prints ms, exit 1 = dead)
# THE ONLY DOORS (an allow-list: a web port can never be relayed):
#   salt-pub  relay:4505 -> <node IP>:4505  (Traefik's hostPort -> Salt publish)
#   salt-req  relay:4506 -> <node IP>:4506  (Traefik's hostPort -> Salt request/auth)
#   ssh       relay:<SSH_WANT or any> -> 127.0.0.1:22  (sshd: key-only root, 00-os-prep.sh)
# Why exactly 4505/4506 on the relay (SALT_FIXED=1): the kit's join.sh sets only `master:`; a minion takes master_port
# from its own config (default 4506) and the PUBLISH port from what the master advertises at auth (Uyuni's 4505), unless
# its own config sets publish_port (salt/channel/client.py, 3006.0). The kit's lessons, break.sh (--dport 4506) and
# probe.sh (dport 4505/4506) use those numbers too. So the relay's ports must be 4505/4506, or every minion needs
# master_port + publish_port (the D-K2 kit change, not applied).
# Config: /etc/osas26/relay.conf (RELAY_SERVER, SALT_FIXED, SSH_WANT, PORT_HOLD, FALLBACK, NODE_IP); see `up`.
set -uo pipefail
BORE_V=v0.6.0
BORE_SHA=e484d1e3acba77169b773f31a5bfb34192d4b660f44a094a658a2522cd2270f7   # bore-v0.6.0-x86_64-unknown-linux-musl.tar.gz (GitHub asset digest, 2025-06-09)
CONF=/etc/osas26/relay.conf; RUN=/run/osas26-relay; W=/root/osas26
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"
RELAY_SERVER=${RELAY_SERVER:-bore.pub}; SALT_FIXED=${SALT_FIXED:-1}; SSH_WANT=${SSH_WANT:-0}
PORT_HOLD=${PORT_HOLD:-600}; FALLBACK=${FALLBACK:-0}
die(){ echo "relay: $*" >&2; exit 1; }
ev(){ install -d -m 0755 "$RUN"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$RUN/events.log" >&2; }
node_ip(){ [ -n "${NODE_IP:-}" ] && { echo "$NODE_IP"; return; }; ip -o -4 route get 1.1.1.1 | sed -n 's/.* src \([^ ]*\).*/\1/p'; }
door(){   # door NAME -> "localhost localport wanted-remote-port probe-kind"
  case $1 in
    salt-pub) echo "$(node_ip) 4505 $([ "$SALT_FIXED" = 1 ] && echo 4505 || echo 0) zmtp" ;;
    salt-req) echo "$(node_ip) 4506 $([ "$SALT_FIXED" = 1 ] && echo 4506 || echo 0) zmtp" ;;
    ssh)      echo "127.0.0.1 22 $SSH_WANT ssh" ;;
    *) die "unknown door '$1' (only salt-pub, salt-req, ssh: web ports are never relayed)" ;;
  esac; }

# End to end: connect to the relay's public port, speak first where the service waits (ZMTP greeting), expect the
# service's first byte back (ZMTP signature 0xff, or "SSH-"). A plain TCP connect would succeed even with a dead client.
probe_raw(){ python3 - "$@" <<'PY'
import socket, sys, time
host, port, kind = sys.argv[1], int(sys.argv[2]), sys.argv[3]
t = time.monotonic()
try:
    s = socket.create_connection((host, port), timeout=8); s.settimeout(8)
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
probe(){ local d p; read -r _ _ _ kind <<<"$(door "$1")"; p=$(cat "$RUN/$1.port" 2>/dev/null) || return 1
  d=$(probe_raw "$RELAY_SERVER" "$p" "$kind") || return 1; echo "$d"; }

tunnel(){
  local name=$1 lhost lport want kind st n=0 busy_since=0 back=2 l p last hold fb
  read -r lhost lport want kind <<<"$(door "$name")"; st=$RUN/$name; install -d -m 0755 "$RUN"
  [ -s "$st.port" ] && want=$(cat "$st.port")            # sticky: a restarted loop asks for the port it had
  while :; do
    n=$((n + 1)); ev "$name: client start #$n (ask $RELAY_SERVER for port $want -> $lhost:$lport)"
    t0=$(date +%s)
    bore local "$lport" --local-host "$lhost" --to "$RELAY_SERVER" --port "$want" 2>&1 | while IFS= read -r l; do
      l=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$l")
      case $l in *"new connection"*|*"connection exited"*) : ;; *) printf '%s %s\n' "$(date -u +%T)" "$l" >> "$st.log" ;; esac
      case $l in *"listening at "*) p=${l##*:}; echo "$p" > "$st.port.new" && mv "$st.port.new" "$st.port"
                                    printf '%s UP %s:%s\n' "$(date -u +%FT%TZ)" "$RELAY_SERVER" "$p" >> "$RUN/events.log" ;; esac
    done
    last=$(tail -n 3 "$st.log" 2>/dev/null)
    if grep -q 'port already in use' <<<"$last"; then
      [ "$busy_since" = 0 ] && busy_since=$(date +%s)
      ev "$name: remote port $want is BUSY on $RELAY_SERVER ($(( $(date +%s) - busy_since )) s so far; a dropped client's port frees when the relay notices)"
      hold=$PORT_HOLD; fb=$FALLBACK; [ "$name" = ssh ] && { hold=${SSH_HOLD:-60}; fb=1; }   # ssh: any port will do
      if [ "$fb" = 1 ] && [ $(( $(date +%s) - busy_since )) -ge "$hold" ]; then
        ev "$name: FALLBACK after ${hold} s: any free port$([ "$name" = ssh ] || echo ' (server.env must then carry the new port: D-K2)')"; want=0; rm -f "$st.port"; fi
      sleep 5; continue
    fi
    busy_since=0
    [ "$want" = 0 ] && [ -s "$st.port" ] && want=$(cat "$st.port")
    if [ $(( $(date +%s) - t0 )) -ge 60 ]; then back=2; else back=$(( back < 15 ? back * 2 : 15 )); fi
    ev "$name: client exited ($(tail -n 1 "$st.log" 2>/dev/null | cut -c1-160)); restart in ${back} s"
    sleep "$back"
  done
}

watch(){
  declare -A fail=()
  while :; do
    for name in salt-pub salt-req ssh; do
      systemctl is-active --quiet "osas26-relay@$name.service" || continue
      [ -s "$RUN/$name.port" ] || continue
      if ms=$(probe "$name"); then
        [ "${fail[$name]:-0}" -ge 1 ] && ev "$name: probe OK again (${ms} ms) after ${fail[$name]} failure(s)"
        fail[$name]=0; printf 'ok %s ms at %s\n' "$ms" "$(date -u +%T)" > "$RUN/$name.probe"
      else
        fail[$name]=$(( ${fail[$name]:-0} + 1 )); printf 'FAIL x%s at %s\n' "${fail[$name]}" "$(date -u +%T)" > "$RUN/$name.probe"
        if [ "${fail[$name]}" -ge "${WATCH_FAILS:-3}" ]; then
          read -r _ lport _ _ <<<"$(door "$name")"
          ev "$name: ${fail[$name]} probes failed end to end: killing its bore client (the loop restarts it on the same port)"
          pkill -f "^bore local $lport " || true; fail[$name]=0
        fi
      fi
    done
    sleep "${WATCH_EVERY:-20}"
  done
}

write_env(){
  local rip; rip=$(getent ahostsv4 "$RELAY_SERVER" | awk 'NR==1{print $1}')
  umask 022
  { echo "# relay.env - RUNNER-HQ's public doors (not secret). Written by lab/runner/relay.sh at $(date -u +%FT%TZ)."
    echo "RELAY_SERVER=$RELAY_SERVER"; echo "RELAY_IP=$rip"
    echo "SALT_PUB_PORT=$(cat "$RUN/salt-pub.port" 2>/dev/null)"; echo "SALT_REQ_PORT=$(cat "$RUN/salt-req.port" 2>/dev/null)"
    echo "SSH_PORT=$(cat "$RUN/ssh.port" 2>/dev/null)"
    echo "SSH_HOSTKEY=$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null | awk '{print $2}')"
    echo "NODE_IP=$(node_ip)"; } > "$W/relay.env"
}

up(){
  local want=() d
  case ${1:-all} in ssh) want=(ssh) ;; salt) want=(salt-pub salt-req) ;; all) want=(ssh salt-pub salt-req) ;; *) die "up ssh|salt|all" ;; esac
  command -v bore >/dev/null || install_bore
  install -d -m 0755 /etc/osas26 "$RUN"; install -d -m 0700 "$W"
  [ -s "$CONF" ] || printf 'RELAY_SERVER=%s\nSALT_FIXED=%s\nSSH_WANT=%s\nPORT_HOLD=%s\nFALLBACK=%s\nNODE_IP=%s\n' \
                      "$RELAY_SERVER" "$SALT_FIXED" "$SSH_WANT" "$PORT_HOLD" "$FALLBACK" "$(node_ip)" > "$CONF"
  install -m 0755 "$(readlink -f "$0")" /usr/local/sbin/osas26-relay
  cat > /etc/systemd/system/osas26-relay@.service <<'EOF'
[Unit]
Description=oSAS26 RUNNER-HQ relay door %i (bore client, supervised)
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/local/sbin/osas26-relay tunnel %i
KillMode=control-group
Restart=always
RestartSec=3
EOF
  cat > /etc/systemd/system/osas26-relay-watch.service <<'EOF'
[Unit]
Description=oSAS26 RUNNER-HQ relay watchdog (end-to-end probes, restarts a dead door)
[Service]
Type=simple
ExecStart=/usr/local/sbin/osas26-relay watch
Restart=always
RestartSec=5
EOF
  systemctl daemon-reload
  for d in "${want[@]}"; do systemctl start "osas26-relay@$d.service"; done
  systemctl start osas26-relay-watch.service
  local ok=1 end=$(( $(date +%s) + ${UP_WAIT:-120} ))
  for d in "${want[@]}"; do
    until [ -s "$RUN/$d.port" ] && probe "$d" >/dev/null; do
      [ "$(date +%s)" -lt "$end" ] || { ev "$d: NOT UP after ${UP_WAIT:-120} s (see $RUN/$d.log)"; ok=0; break; }; sleep 2; done
    [ -s "$RUN/$d.port" ] && ev "$d: $RELAY_SERVER:$(cat "$RUN/$d.port") (probe $(probe "$d" || echo FAIL) ms)"
  done
  write_env
  if [ "$SALT_FIXED" = 1 ]; then
    for d in "${want[@]}"; do case $d in salt-*) read -r _ lp _ _ <<<"$(door "$d")"
      [ "$(cat "$RUN/$d.port" 2>/dev/null)" = "$lp" ] || { ev "$d: the relay did not give port $lp (busy?): the kit needs exactly 4505/4506"; ok=0; } ;; esac; done
  fi
  [ "$ok" = 1 ]
}

status(){
  [ -s "$W/relay.env" ] && grep -v '^#' "$W/relay.env"
  for d in salt-pub salt-req ssh; do
    printf '%-9s %-8s port %-6s probe %-28s client starts %s\n' "$d" "$(systemctl is-active "osas26-relay@$d.service" 2>/dev/null)" \
      "$(cat "$RUN/$d.port" 2>/dev/null || echo -)" "$(cat "$RUN/$d.probe" 2>/dev/null || echo -)" \
      "$(grep -c "$d: client start" "$RUN/events.log" 2>/dev/null || true)"
  done
}

down(){ if [ -n "${1:-}" ]; then systemctl stop "osas26-relay@$1.service"; rm -f "$RUN/$1.port"
        else systemctl stop osas26-relay-watch.service 'osas26-relay@*.service' 2>/dev/null; rm -f "$RUN"/*.port; fi; }

install_bore(){
  local S; S=$(mktemp -d)
  curl -fsSL --retry 3 -o "$S/bore.tgz" "https://github.com/ekzhang/bore/releases/download/$BORE_V/bore-$BORE_V-x86_64-unknown-linux-musl.tar.gz"
  echo "$BORE_SHA  $S/bore.tgz" | sha256sum -c --quiet - || { rm -rf "$S"; die "bore $BORE_V checksum MISMATCH: not installed"; }
  tar -xzf "$S/bore.tgz" -C "$S" && install -m 0755 "$S/bore" /usr/local/bin/bore; rm -rf "$S"
  bore --version
}

case ${1:-} in
  install) install_bore ;;
  up) [ "$(id -u)" = 0 ] || die "run as root"; up "${2:-all}" ;;
  status) status ;;
  down) down "${2:-}" ;;
  tunnel) tunnel "${2:?door}" ;;
  watch) watch ;;
  probe) probe "${2:?door}" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
