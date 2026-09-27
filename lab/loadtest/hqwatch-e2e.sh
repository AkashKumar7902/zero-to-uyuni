#!/usr/bin/env bash
# lab/loadtest/hqwatch-e2e.sh - the HQ table's safety net (attendee/hqwatch.sh) with REAL Salt, on a runner that plays one
# Killercoda sandbox: root, systemd, the kit in /root/osas26 as the scenario puts it, preinstall.sh done (sandbox.yml
# mode=hqwatch runs it). "Uyuni HQ" is a stand-in: a second salt-master from the same Salt 3006 bundle, on 127.0.0.2
# with its own config, keys and sockets, so every answer is real Salt's: a pending key, salt-key -a (HQ says yes),
# salt-key -r (what lab/runner/hq-table.sh's CAP guard runs: HQ says no), and a stopped master (HQ goes quiet).
# The watcher runs with the show's numbers (a 5-s tick, a knock every 30 s, 3 knocks); only the 10-minute "never said
# yes" limit is shortened (HQWATCH_ACCEPT_S=60) for its own case. Prints PASS/FAIL/INFO lines only.
set -u
K=/root/osas26; PY=/usr/lib/venv-salt-minion/bin/python; H=/etc/osas26-hq-standin; TTY=/tmp/hqwatch-e2e.tty
pass=0; fail=0
ok(){ printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }; bad(){ printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
info(){ printf 'INFO  %s\n' "$1"; }
until_t(){ local _; for _ in $(seq "$2"); do eval "$1" && return 0; sleep 1; done; return 1; }
[ "$(id -u)" = 0 ] && [ -x "$PY" ] && [ -x $K/join.sh ] && [ -x $K/hqwatch.sh ] \
  || { echo "FAIL  run as root after preinstall.sh, with the kit in $K"; exit 1; }

# ---- the stand-in Uyuni HQ: salt-master 3006 from the bundle on 127.0.0.2 (no "salt-master" in its command line, so
#      solo.sh down, which stops YOUR OWN HQ's master, never touches it) ------------------------------------------------
install -d -m 0700 $H $H/pki; install -d /srv/osas26-hq-standin /var/cache/osas26-hq-standin
cat > $H/master <<EOF
interface: 127.0.0.2
auto_accept: False
worker_threads: 2
pki_dir: $H/pki
cachedir: /var/cache/osas26-hq-standin
sock_dir: /var/run/osas26-hq-standin
pidfile: /var/run/osas26-hq-standin.pid
log_file: /var/log/osas26-hq-standin.log
key_logfile: /var/log/osas26-hq-standin-key.log
file_roots: {base: [/srv/osas26-hq-standin]}
EOF
for c in master:salt_master key:salt_key cli:salt_main; do
  cat > "/usr/local/sbin/hq-standin-${c%%:*}" <<EOF
#!$PY
import sys, warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from salt.scripts import ${c#*:}
sys.argv[1:1] = ["-c", "$H"]
${c#*:}()
EOF
  chmod 0755 "/usr/local/sbin/hq-standin-${c%%:*}"
done
printf '[Unit]\nDescription=hqwatch-e2e: a stand-in Uyuni HQ (salt-master on 127.0.0.2)\n[Service]\nExecStart=/usr/local/sbin/hq-standin-master\n' \
  > /etc/systemd/system/osas26-hq-standin.service
systemctl daemon-reload
greets(){ timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.2/4506 && head -c 1 <&3' 2>/dev/null | od -An -tx1 | grep -q ff; }
hq(){ systemctl "$1" osas26-hq-standin; [ "$1" = start ] && until_t greets 40; }
hqkey(){ /usr/local/sbin/hq-standin-key "$@" >/dev/null 2>&1; }
hq start && ok "the stand-in Uyuni HQ (salt-master $("$PY" -c 'import salt.version; print(salt.version.__version__)') from the bundle) greets on 127.0.0.2:4506" \
  || { bad "the stand-in HQ did not start: $(tail -3 /var/log/osas26-hq-standin.log)"; exit 1; }

# ---- the sandbox side: server.env points at the stand-in; the game is off; the notes go to a file ------------------
printf 'FQDN=uyuni.127-0-0-2.sslip.io\nSERVER_IP=127.0.0.2\nKEY=1-osas26-fleet\nGAME_URL=\nHQ_MASTER_FINGER_TAIL=\nMODE=solo\n' > $K/server.env
export SERVER_ENV_URL=file://$K/server.env HQWATCH_TTYS=$TTY HQWATCH_LOG=/tmp/hqwatch-e2e.switch.log
mode(){ cat /etc/osas26-mode 2>/dev/null; }
myid(){ cat /etc/osas26-id 2>/dev/null; }
watching(){ pgrep -f "hqwatch.sh $1 " >/dev/null; }
pending(){ [ -e "$H/pki/minions_pre/$1" ]; }
switched(){ until_t '[ "$(mode)" = solo ] && grep -q "salt-key -a" '$TTY "$1"; }
own_yes(){ until_t "salt-key -l un 2>/dev/null | grep -qx '$1'" 40 && salt-key -y -a "$1" >/dev/null \
             && until_t "salt -t 3 '$1' test.ping 2>/dev/null | grep -q True" 60; }
hjoin(){ : > $TTY; bash $K/join.sh --hq "$1" > "/tmp/hqwatch-e2e.join-$1.log" 2>&1; }

# 1. HQ says yes: the watcher stays quiet through three knock rounds
hjoin e2ea; id=$(myid)
grep -q 'this sandbox gets YOUR OWN HQ by itself' /tmp/hqwatch-e2e.join-e2ea.log && watching "$id" \
  && ok "join.sh --hq: the banner, then the watcher runs ($id)" || bad "no watcher after join.sh --hq"
until_t "pending $id" 60 && hqkey -y -a "$id" \
  && until_t "[ -s /etc/venv-salt-minion/pki/minion/minion_master.pub ] && ss -Htn state established '( dport = :4505 )' | grep -q 127.0.0.2" 90 \
  && ok "HQ said yes (salt-key -a on the stand-in): the minion saved HQ's key and holds its 4505 line" || bad "accept on the stand-in"
sleep 95
[ "$(mode)" = hq ] && [ ! -s $TTY ] && watching "$id" && /usr/local/sbin/hq-standin-cli -t 10 "$id" test.ping 2>/dev/null | grep -q True \
  && ok "95 s later (three knocks answered): still on HQ, no note, HQ's test.ping True" || bad "accepted: mode $(mode), note: $(cat $TTY)"

# 2. HQ goes quiet later: the minion stops, YOUR OWN HQ by itself, and it really works
t0=$(date +%s); systemctl stop osas26-hq-standin; switched 200; t1=$(date +%s); nid=$(myid)
[ "$(mode)" = solo ] && [ "$nid" != "$id" ] && grep -q 'Uyuni HQ went quiet' $TTY && grep -q "Your next step: salt-key -a $nid" $TTY \
  && grep -qx 'master: my-hq.osas26.test' /etc/venv-salt-minion/minion.d/osas26.conf && ! watching "$id" \
  && ok "HQ went quiet: YOUR OWN HQ by itself, $((t1 - t0)) s after HQ stopped (3 knocks, 30 s apart), with a note" || bad "HQ quiet: $(cat $TTY)"
info "the note: $(tr -d '\033' < $TTY | sed 's/\[1;33m//; s/\[0m//' | grep -v '^$' | head -2 | tr '\n' ' ')"
own_yes "$nid" && ok "and it works: the new key waits on YOUR master; salt-key -a, then test.ping True" || bad "own HQ after the switch"

# 3. HQ says no (the CAP guard's salt-key -r)
hq start; hjoin e2eb; id=$(myid)
until_t "pending $id" 60; t0=$(date +%s); hqkey -y -r "$id"; switched 90; t1=$(date +%s); nid=$(myid)
[ "$(mode)" = solo ] && grep -q "Uyuni HQ said no to this sandbox's key" $TTY && grep -q "has rejected this minion's public key" /var/log/venv-salt-minion.log \
  && ok "HQ said no (salt-key -r, as the CAP guard runs it): YOUR OWN HQ by itself $((t1 - t0)) s later" || bad "refused: $(cat $TTY)"
own_yes "$nid" && ok "the refused sandbox runs its own HQ: salt-key -a, test.ping True" || bad "own HQ after the refusal"

# 4. HQ never says yes (the limit is 10 minutes on the day; 60 s here)
t0=$(date +%s); HQWATCH_ACCEPT_S=60 hjoin e2ec; id=$(myid); until_t "pending $id" 60; switched 120; t1=$(date +%s)
[ "$(mode)" = solo ] && grep -q 'Uyuni HQ has not said yes' $TTY \
  && ok "HQ never said yes (HQWATCH_ACCEPT_S=60): YOUR OWN HQ by itself $((t1 - t0)) s after join.sh" || bad "never yes: $(cat $TTY)"

# 5. MODE=solo (the room): no watcher at all
: > $TTY; bash $K/join.sh e2ed > /tmp/hqwatch-e2e.join-e2ed.log 2>&1; sid=$(myid)
[ "$(mode)" = solo ] && ! pgrep -f 'hqwatch.sh' >/dev/null && ! grep -q 'by itself' /tmp/hqwatch-e2e.join-e2ed.log && [ ! -s $TTY ] \
  && ok "MODE=solo (the room): no watcher, no note" || bad "MODE=solo started a watcher"
own_yes "$sid" && ok "and the room's path is unchanged: salt-key -a, test.ping True" || bad "MODE=solo own HQ"

systemctl stop osas26-hq-standin; bash $K/solo.sh down
echo; echo "hqwatch-e2e: $pass passed, $fail to fix"; [ "$fail" = 0 ]
