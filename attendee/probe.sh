#!/usr/bin/env bash
# probe.sh blueprint|lines [--wait]|card|incident|replay - LEARNING PROBES: small, read-only facts about THIS sandbox
# that prove a concept to the whole room (the big screen shows counts only, never names). The verify scripts and
# crew.sh call it; it is safe to run by hand. It changes nothing on this machine.
#   blueprint        how many volumes (PersistentVolumeClaims) your rendered blueprint has, and where it came from
#   lines [--wait]   who dialled whom: lines this machine opened to HQ's doors 4505/4506, and Salt doors LISTENING here
#                    (expect 0). --wait: first wait up to 3 min until HQ trusts this machine (a pending minion holds
#                    only the 4506 line), then report once.
#   card             the crew card HQ's state wrote here: did the order arrive, and does its Blueprint box match
#                    THIS machine's own Level 1?
#   incident         after Level 4: which fault, is the EFFECTIVE master right, is the port rule gone, is the minion up?
#   replay           re-tell the game every fact that is true here now (crew.sh runs it when a crew links late)
# Each prints one JSON object (replay prints nothing) and blueprint/lines/card also tell the game (game.sh rules).
set -u
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
SALT=${SALT_CALL:-venv-salt-call}
MOTD=${MOTD_FILE:-/etc/motd}
BP=${BLUEPRINT:-/root/uyuni.yaml}
PRE=${PRERENDERED:-$D/uyuni.yaml.prerendered}
FQDN_FILE=${FQDN_FILE:-/etc/osas26-fqdn}
ID_FILE=${ID_FILE:-/etc/osas26-id}
BREAK_FILE=${BREAK_FILE:-/root/.osas26-break}
EV_FILE=${EVIDENCE_FILE:-/root/.osas26-evidence}
PKI=${MINION_PKI:-/etc/venv-salt-minion/pki/minion}
ACH=${ACH_DIR:-/etc/osas26}
QD=$ACH/quests
WAIT_S=${PROBE_WAIT_S:-180}

b(){ if "$@"; then echo true; else echo false; fi; }
n_est(){ ss -Htn state established "( dport = :$1 )" 2>/dev/null | grep -c . ; }
n_listen(){ ss -Htln '( sport = :4505 or sport = :4506 )' 2>/dev/null | grep -c . ; }
eff_master(){ timeout 20 "$SALT" --local config.get master 2>/dev/null | sed -n '2p' | tr -d ' '; }
clamp(){ local v=${1:-0}; [[ $v =~ ^[0-9]+$ ]] || v=0; [ "$v" -gt "$2" ] && v=$2; echo "$v"; }

blueprint(){
  local n src=helm
  n=$(clamp "$(grep -c '^kind: PersistentVolumeClaim' "$BP" 2>/dev/null)" 200)
  cmp -s "$BP" "$PRE" 2>/dev/null && src=catchup
  printf '{"pvcs":%s,"source":"%s"}' "$n" "$src"
}
lines(){
  printf '{"out4505":%s,"out4506":%s,"listen":%s}' "$(clamp "$(n_est 4505)" 9)" "$(clamp "$(n_est 4506)" 9)" \
    "$(clamp "$(n_listen)" 9)"
}
blueprint_ok(){ [ "$(clamp "$(grep -c '^kind: PersistentVolumeClaim' "$BP" 2>/dev/null)" 200)" -ge 20 ]; }   # a real render
trusted_now(){ [ -s "$PKI/minion_master.pub" ] && [ "$(n_est 4505)" -ge 1 ]; }
card(){
  local order box file
  order=$(b grep -qF 'ORDER FROM HQ: find out what happened' "$MOTD")
  if grep -q '\[x\] Blueprint' "$MOTD" 2>/dev/null; then box=true; else box=false; fi
  file=$(b test -s "$BP")
  printf '{"order":%s,"box_matches_machine":%s}' "$order" "$(b test "$box" = "$file")"
}
break_mode(){ local m; m=$(tr -cd 'a-z' < "$BREAK_FILE" 2>/dev/null); case "$m" in dns|port) echo "$m" ;; *) echo none ;; esac; }
master_is_hq(){ local fq; fq=$(cat "$FQDN_FILE" 2>/dev/null); [ -n "$fq" ] && [ "$(eff_master)" = "$fq" ]; }
incident(){
  printf '{"mode":"%s","master_ok":%s,"port_rule":%s,"minion_active":%s}' "$(break_mode)" \
    "$(b master_is_hq)" \
    "$(b iptables -C OUTPUT -p tcp --dport 4506 -j REJECT 2>/dev/null)" \
    "$(b systemctl is-active --quiet venv-salt-minion)"
}
port4506(){
  local fq; fq=$(cat "$FQDN_FILE" 2>/dev/null)
  if [ -n "$fq" ] && timeout 3 bash -c "</dev/tcp/$fq/4506" 2>/dev/null; then echo open; else echo blocked; fi
}
with_replay(){ if [ "$1" = '{}' ]; then echo '{"replay":true}'; else printf '%s' "${1%\}},\"replay\":true}"; fi; }

replay(){
  local id c q tier
  blueprint_ok && game_post l1.render "$(with_replay "$(blueprint)")"
  c=$(tr -cd 'A-Z0-9' < "$EV_FILE" 2>/dev/null)
  case "$c" in D3|D2|N2) game_post l1.evidence "{\"sealed\":true,\"case\":\"$c\",\"replay\":true}" ;; esac
  id=$(tr -cd 'a-z0-9-' < "$ID_FILE" 2>/dev/null)
  [[ $id =~ ^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$ ]] \
    && game_post l2.join "{\"minion_id\":\"$id\",\"port4506\":\"$(port4506)\",\"replay\":true}"
  trusted_now && game_post l2.lines "$(with_replay "$(lines)")"
  grep -qF 'ORDER FROM HQ: find out what happened' "$MOTD" 2>/dev/null && game_post l3.card "$(with_replay "$(card)")"
  if [ -e "$ACH/ach.doctor" ]; then game_post l4.fixed "$(with_replay "$(incident)")"
  elif [ "$(break_mode)" != none ]; then game_post l4.break "{\"mode\":\"$(break_mode)\",\"replay\":true}"; fi
  for q in "$QD"/*.done; do
    [ -e "$q" ] || continue
    q=$(basename "$q" .done); [[ $q =~ ^(R[1-7]|F[1-7]|D[1-5]|X1)$ ]] || continue
    case ${q:0:1} in R) tier=recon ;; F) tier=field ;; *) tier=deep ;; esac
    game_post quest "{\"id\":\"$q\",\"tier\":\"$tier\",\"replay\":true}"
  done
  return 0
}

wait_lines(){   # one waiter at a time; gives up quietly after WAIT_S seconds (a machine that is not trusted yet)
  mkdir /tmp/osas26-probe-lines.lock 2>/dev/null || return 0
  trap 'rmdir /tmp/osas26-probe-lines.lock 2>/dev/null' EXIT
  local waited=0
  until trusted_now; do
    [ "$waited" -ge "$WAIT_S" ] && return 0
    sleep 5; waited=$((waited + 5))
  done
  local j; j=$(lines); echo "$j"; game_post l2.lines "$j"
}

case "${1:-}" in
  blueprint) j=$(blueprint); echo "$j"; blueprint_ok && game_post l1.render "$j" ;;
  lines)     if [ "${2:-}" = --wait ]; then wait_lines; else j=$(lines); echo "$j"; game_post l2.lines "$j"; fi ;;
  card)      j=$(card);      echo "$j"; game_post l3.card "$j" ;;
  incident)  incident; echo ;;                 # verify4.sh posts it together with its verdict
  replay)    replay ;;
  *) echo "usage: probe.sh blueprint | lines [--wait] | card | incident | replay"; exit 1 ;;
esac
exit 0
