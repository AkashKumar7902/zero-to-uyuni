#!/usr/bin/env bash
# lab/loadtest/cf-doors.sh - the SANDBOX side of RUNNER-HQ's cloudflare-quick relay (lab/runner/relay-cf.sh). It is the
# proposed kit change D-K3 (RUNNER-HQ-REPORT.md §9), used here by the load test and sandbox.yml; the kit is unchanged.
# Two local forwarders, supervised: 127.0.0.1:4505 -> CF_PUB_HOST and 127.0.0.1:4506 -> CF_REQ_HOST
# (`cloudflared access tcp`, one WebSocket per Salt connection). server.env then says SERVER_IP=127.0.0.1, so join.sh's
# "/etc/hosts: SERVER_IP FQDN" line points the minion at them, and break.sh / probe.sh keep their 4505/4506 numbers.
# Every 60 s it re-reads server.env (SERVER_ENV_URL, as game.sh does): when HQ's quick tunnels got new names (a
# cloudflared restart on HQ), the forwarders follow. With any other RELAY it exits at once and changes nothing.
# Runs in the foreground: `cf-doors.sh &`, or a systemd unit.
set -uo pipefail
CF_V=2026.9.3
CF_SHA=77e26d8d900e0b8469f416239d14b5f296525fdf79fee6f511ef55609e3fbac2   # cloudflared-linux-amd64 (GitHub asset digest)
URL=${SERVER_ENV_URL:-https://raw.githubusercontent.com/AkashKumar7902/zero-to-uyuni/main/attendee/server.env}
F=${CF_DOORS_ENV:-/tmp/cf-doors.env}; L=${CF_DOORS_LOG:-/tmp/cf-doors.log}
log(){ printf '%s %s\n' "$(date -u +%T)" "$*" >> "$L"; }
fetch(){ curl -fsS --max-time 10 -o "$F.new" "$URL" 2>/dev/null && grep -q '^FQDN=' "$F.new" && mv "$F.new" "$F"; rm -f "$F.new"; }
v(){ sed -n "s/^$1=//p" "$F" | head -1; }
fetch || { log "no server.env from $URL"; exit 1; }
[ "$(v RELAY)" = cloudflare-quick ] || { log "RELAY=$(v RELAY): nothing to do"; exit 0; }
if ! command -v cloudflared >/dev/null; then
  T=$(mktemp); curl -fsSL --retry 3 -o "$T" "https://github.com/cloudflare/cloudflared/releases/download/$CF_V/cloudflared-linux-amd64"
  echo "$CF_SHA  $T" | sha256sum -c --quiet - || { rm -f "$T"; log "cloudflared checksum MISMATCH"; exit 1; }
  install -m 0755 "$T" /usr/local/bin/cloudflared; rm -f "$T"
fi
declare -A pid=() host=()
trap 'kill "${pid[@]}" 2>/dev/null; exit 0' INT TERM
while :; do
  for d in pub:4505 req:4506; do n=${d%%:*}; p=${d#*:}; h=$(v "CF_${n^^}_HOST")
    if [ -n "$h" ] && { [ "${host[$n]:-}" != "$h" ] || ! kill -0 "${pid[$n]:-0}" 2>/dev/null; }; then
      [ -n "${pid[$n]:-}" ] && kill "${pid[$n]}" 2>/dev/null
      cloudflared access tcp --hostname "$h" --url "127.0.0.1:$p" >> "$L.$n" 2>&1 & pid[$n]=$!
      log "door $p -> $h (forwarder pid ${pid[$n]}$([ -n "${host[$n]:-}" ] && [ "${host[$n]}" != "$h" ] && echo ", NEW name"))"; host[$n]=$h
    fi
  done
  sleep 60; fetch || log "server.env refresh failed (keeping $(v CF_PUB_HOST))"
done
