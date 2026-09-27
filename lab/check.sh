#!/usr/bin/env bash
# check.sh - HQ's daily health check (PLAN §5.11 + FREE-GOLDEN §8.2), about a minute, read-only.
#   ssh golden /root/zero-to-uyuni/lab/check.sh
# Prints OK / FAIL / INFO lines; exits 1 if any FAIL. DISK_ALARM=85 (percent) by default.
# No final `exit` (rehearsal fix F6): the exit code comes from the EXIT trap, and the game's lines are sourced at the
# end when the hooks are installed (PLAN §5.16.3; the line below is the one DEPLOY §6.1 greps for).
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
lab_env
fail=0
trap 'exit $fail' EXIT
ok(){ printf 'OK    %s\n' "$*"; }; bad(){ printf 'FAIL  %s\n' "$*"; fail=1; }; info(){ printf 'INFO  %s\n' "$*"; }
k(){ timeout 30 kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
# --- the cluster and Uyuni
n=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l); [ "$n" -ge 1 ] && ok "node Ready ($n)" || bad "node not Ready"
notready=$(kubectl -n uyuni get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]!=a[2] && $3!="Completed") print $1" "$2" "$3}')
[ -z "$notready" ] && ok "uyuni pods Ready: $(kubectl -n uyuni get pods --no-headers 2>/dev/null | awk '{print $1" "$2}' | tr '\n' ' ')" || bad "uyuni pods not Ready: $notready"
code=$(curl -sk -o /dev/null -m 15 -w '%{http_code}' "https://${FQDN}/rhn/manager/api/api/getVersion"); [ "$code" = 200 ] && ok "getVersion 200" || bad "getVersion $code"
# rehearsal F2: CoreDNS keeps the resolv.conf of the network it started on; the db reverse-resolves every client
dnsip=$(kubectl -n kube-system get svc rke2-coredns-rke2-coredns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if command -v dig >/dev/null && [ -n "$dnsip" ]; then
  st=$(dig +tries=1 +time=3 -x 10.42.0.254 @"$dnsip" 2>/dev/null | sed -n 's/.*status: \([A-Z]*\),.*/\1/p')
  a=$(dig +short +tries=1 +time=3 "$FQDN" @"$dnsip" 2>/dev/null | tail -1)
  { [ "$st" = NXDOMAIN ] || [ "$st" = NOERROR ]; } && [ "$a" = "$PUB_IP" ] && ok "cluster DNS: PTR $st, $FQDN -> $a" \
    || bad "cluster DNS (PTR ${st:-timeout}, $FQDN -> ${a:-nothing}): kubectl -n kube-system rollout restart deploy/rke2-coredns-rke2-coredns"
fi
# --- disk, memory, Taskomatic
lp=/opt/local-path-provisioner; pct=$(df --output=pcent "$lp" | tail -1 | tr -dc 0-9); free=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
A=${DISK_ALARM:-85}
[ "$pct" -lt "$A" ] && ok "disk $lp ${pct}% used (alarm at ${A}%; liveness fails at 95%), / ${free} GB free" || bad "disk $lp ${pct}% used (alarm at ${A}%), / ${free} GB free"
info "memory: $(free -g | awk '/^Mem:/{print "used "$3" of "$2" GB, available "$7" GB"}')"
oom=$(k sh -c 'grep -c OutOfMemoryError /var/log/rhn/rhn_taskomatic_daemon.log 2>/dev/null || echo 0' 2>/dev/null | tail -1)
[ "${oom:-0}" = 0 ] && ok "Taskomatic OutOfMemoryError count 0" || bad "Taskomatic OutOfMemoryError count ${oom} (#11817): restart taskomatic"
# --- Salt keys and the doors
keys=$(k salt-key --out=json 2>/dev/null)
if [ -n "$keys" ]; then
  acc=$(jq -r '.minions[]' <<<"$keys" | grep -c . || true); pend=$(jq -r '.minions_pre[]' <<<"$keys" | grep -c . || true)
  pa=$(jq -r '.minions_pre[]' <<<"$keys" | grep -c '^osas26-' || true)
  info "salt keys: accepted $acc, pending $pend ($pa pending osas26-*; should be 0 outside test windows)"
else bad "salt-key did not answer"; fi
code=$(curl -sk -o /dev/null -m 15 -w '%{http_code}' "https://${FQDN}/cobbler_api"); [ "$code" = 403 ] && ok "cobbler_api 403" || bad "cobbler_api $code (want 403)"
# --- the host guard and the Salt window (FREE-GOLDEN §6.5: the guard is the only barrier for 443)
np=$(kubectl get svc -A --no-headers 2>/dev/null | grep -c NodePort || true); [ "$np" = 0 ] && ok "no NodePort services" || bad "$np NodePort service(s)"
if [ "${RUNNER:-0}" = 1 ]; then
  # a GitHub runner (lab/runner/): no inbound path but the relay's tunnels (4505, 4506, 22), so no guard to check
  if [ -s "$W/relay.env" ]; then info "runner: no host guard; relay doors: $(sed -n 's/^\(SALT_PUB_PORT\|SALT_REQ_PORT\|SSH_PORT\|RELAY_SERVER\)=//p' "$W/relay.env" | tr '\n' ' ')"
  else info "runner: no host guard; relay not started"; fi
  for u in salt-pub salt-req ssh; do systemctl is-active --quiet "osas26-relay@$u.service" && info "relay door $u: $(cat /run/osas26-relay/$u.probe 2>/dev/null || echo 'no probe yet')"; done
  systemctl is-enabled --quiet osas26-accept.timer 2>/dev/null && info "timer osas26-accept: next $(systemctl show osas26-accept.timer -p NextElapseUSecRealtime --value 2>/dev/null)"
else
  if nft list table inet osas26_guard >/dev/null 2>&1; then
    gi=$(nft list chain inet osas26_guard pre 2>/dev/null | sed -n 's/.*iifname != "\([^"]*\)".*/\1/p' | head -1)
    [ "$gi" = "$PUB_IF" ] && ok "guard present on $gi (80/443 and the RKE2 ports closed there)" || bad "guard filters '$gi', but the public interface is $PUB_IF"
  else bad "guard ABSENT: systemctl restart osas26-guard (80/443 may be public!)"; fi
  systemctl is-enabled --quiet osas26-guard.service && ok "guard enabled at boot" || bad "osas26-guard.service is not enabled"
  systemctl show rke2-server -p Requires --value | grep -qw osas26-guard.service && ok "rke2-server Requires the guard" || bad "rke2-server does not Require osas26-guard.service"
  if nft list set inet osas26_guard salt_ok 2>/dev/null | grep -q '0\.0\.0\.0/0'; then
    now=$(date -u +%s); s=$(date -u -d '2026-10-03 06:25:00 UTC' +%s); e=$(date -u -d '2026-10-03 10:30:00 UTC' +%s)
    if [ "$now" -ge "$s" ] && [ "$now" -lt "$e" ]; then ok "Salt window OPEN (the show window)"
    elif systemctl is-active --quiet osas26-salt-autoclose.timer; then info "Salt window OPEN for a test (auto-close pending)"
    else bad "Salt window OPEN outside the show window with no auto-close: osas26-salt-window close"; fi
  else ok "Salt window CLOSED"; fi
  lok=$(nft list set inet osas26_guard lab_ok 2>/dev/null | sed -n 's/.*elements = { \(.*\) }.*/\1/p'); info "lab_ok (demo VMs): ${lok:-none}"
  for tm in osas26-salt-open osas26-accept osas26-salt-close; do
    nx=$(systemctl show "$tm.timer" -p NextElapseUSecRealtime --value 2>/dev/null)
    if systemctl is-enabled --quiet "$tm.timer" 2>/dev/null; then info "timer $tm: next ${nx:-none}"; else info "timer $tm: NOT enabled"; fi
  done
fi
# --- ssh stays key-only
[ -d /run/sshd ] || install -d -m 0755 /run/sshd                  # socket-activated sshd: absent while idle
ST=$(sshd -T 2>/dev/null)   # captured: `sshd -T | grep -q` under pipefail fails on SIGPIPE
grep -qx 'passwordauthentication no' <<<"$ST" && grep -qx 'kbdinteractiveauthentication no' <<<"$ST" \
  && grep -qxE 'permitrootlogin (prohibit-password|without-password)' <<<"$ST" && ok "sshd key-only (ports $(awk '$1=="port"{print $2}' <<<"$ST" | tr '\n' ' '))" || bad "sshd is NOT key-only"
# --- no game state left from rehearsals
left=$(cd "$W" && ls ach.log evidence-count room-status outage-roster 2>/dev/null | tr '\n' ' ')
[ -z "$left" ] && ok "no game state files left from rehearsals" || info "game state files present: $left (FORCE=1 cleanup.sh before the show)"
# the game's lines (PLAN §5.16.3), once golden-hooks/install.sh has put them there
if [ -f /usr/local/share/osas26/check-game.sh ]; then
. /usr/local/share/osas26/check-game.sh
fi
