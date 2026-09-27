#!/usr/bin/env bash
# quest.sh - Geeko Corp SIDE QUESTS: optional hands-on puzzles for anyone waiting for the room. Never ranked, never
# timed, never shown with your crew name. Your answers stay in this sandbox; the game only hears "a crew finished
# quest R3" (the big screen's Discovery Wall shows counts, anonymous and delayed).
#   /root/osas26/quest.sh                 list the side quests you can do now
#   /root/osas26/quest.sh show R3         the story, the command(s), the question
#   /root/osas26/quest.sh answer R3 WORD  check your answer (try as often as you like)
#   /root/osas26/quest.sh start D2        (D2 only) begin the quest that changes something; then: quest.sh check D2
# Three ways to check (GAME-BIBLE §7.9): LIVE = computed on this machine now (R4 R6 F3 F4 F6 F7), HASH = compared with
# a SHA-256 of the fixed answer (the answer is not in this file), STATE = the machine really changed (D2).
# Safe by construction: no quest restarts or breaks the minion, edits minion.d or keys, needs apt, prints all of
# pillar or loads HQ (the heaviest is one state.apply of one SLS). Quests open by LOCAL facts, so they work offline.
# Every command and expected output was verified with real Salt 3006.9 and a real render of server-helm 2026.8.0.
# YOUR OWN HQ (solo.sh): every quest works against your own master too, with its own words where the story differs
# (R3 R4 R5 R6 R7 F2 F3 F4 F7 D2). D3 and D4 read files only Uyuni writes, so they are for the HQ table.
set -u
trap '' PIPE        # piped into head or grep, a solve still counts: output may be cut, the rest of the script runs
D=$(dirname "$0")
# shellcheck source=game.sh
. "$D/game.sh"
# shellcheck source=solo.sh
. "$D/solo.sh"
SALT=${SALT_CALL:-venv-salt-call}
LOG=${MINION_LOG:-/var/log/venv-salt-minion.log}
PKI=${MINION_PKI:-/etc/venv-salt-minion/pki/minion}
BP=${BLUEPRINT:-/root/uyuni.yaml}
MOTD=${MOTD_FILE:-/etc/motd}
ACH=${ACH_DIR:-/etc/osas26}
QD=$ACH/quests
FQDN_FILE=${FQDN_FILE:-/etc/osas26-fqdn}
BREAK_FILE=${BREAK_FILE:-/root/.osas26-break}
ID_FILE=${ID_FILE:-/etc/osas26-id}
SERVER_ENV=${SERVER_ENV:-${SERVER_ENV_FILE:-/tmp/server.env}}; [ -s "$SERVER_ENV" ] || SERVER_ENV=$D/server.env

G=$'\033[1;32m'; Y=$'\033[1;33m'; C=$'\033[1;36m'; N=$'\033[0m'
sha(){ if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -c1-64; }
norm(){ printf '%s' "$*" | tr 'A-Z' 'a-z' | tr -d " \t\"'\`" | sed -E 's#^~/#/root/#; s#[.]+$##'; }
hash_of(){ printf '%s' "$1" | sha; }
first(){ sed -n '2p' | tr -d ' '; }                         # salt-call prints "local:" then the value, indented

# ---------- prerequisites (all local, all offline) ----------
has_bp(){ test -s "$BP"; }
joined(){ test -s "$ID_FILE"; }
trusted(){ joined && test -s "$PKI/minion_master.pub"; }
ordered(){ grep -qF 'ORDER FROM HQ: find out what happened' "$MOTD" 2>/dev/null; }
broke(){ test -s "$BREAK_FILE"; }
healthy(){ local m; m=$(timeout 20 "$SALT" --local config.get master 2>/dev/null | first)
           test -n "$m" && test "$m" = "$(cat "$FQDN_FILE" 2>/dev/null)" \
           && ! iptables -C OUTPUT -p tcp --dport 4506 -j REJECT 2>/dev/null; }
fixed(){ broke && { test -e "$ACH/ach.doctor" || healthy; }; }
org(){ local o; o=$(timeout 25 "$SALT" pillar.get org_id 2>/dev/null | first); case $o in ''|*[!0-9]*) echo 1 ;; *) echo "$o" ;; esac; }
central(){ ! solo_on; }                                   # Uyuni HQ (the HQ table), not your own
fault_mode(){ local m; m=$(tr -cd 'a-z' < "$BREAK_FILE" 2>/dev/null); case "$m" in dns|port) echo "$m" ;; esac; }
# Quest X1's captured diaries (real Salt 3006.9, geeko-hq ideation/learning-design/verification/salt-lab-transcript.md
# §3). Replace them with the G3 captures from a real Killercoda sandbox joined to HQ when those exist.
X1_DNS_LOG="[salt.utils.network:2215][ERROR   ] DNS lookup or connection check of 'uyuni.osas26.invalid' failed.
[salt.minion       :142 ][ERROR   ] Master hostname: 'uyuni.osas26.invalid' not found or not responsive. Retrying in 30 seconds"
X1_PORT_LOG="[salt.minion :1155][ERROR   ] Error while bringing up minion for multi-master. Is master at 127.0.0.1 responding? The error message was Unable to sign_in to master: Attempt to authenticate with the salt master failed with timeout error"

# id | tier | minutes | title | needs (function names, all must pass) | where it opens (said kindly when locked)
QUESTS='R1|recon|2|Two doors|has_bp|Level 1
R2|recon|2|Salt'"'"'s own disks|has_bp|Level 1
R3|recon|2|Your team ticket|joined|Level 2
R4|recon|3|Your ID card|joined|Level 2
R5|recon|2|The knock log|trusted|Level 2
R6|recon|3|No doors here|trusted|Level 2
R7|recon|3|HQ'"'"'s diary entry|ordered|Level 3
F1|field|3|HQ'"'"'s memory map|has_bp|Level 1
F2|field|3|Where orders live|has_bp ordered|Level 3
F3|field|4|Trust goes both ways|trusted|Level 2
F4|field|3|Your name at HQ|joined|Level 2
F5|field|4|The recipe asks your machine|ordered|Level 3
F6|field|4|The diary'"'"'s own words|fixed|Level 4, after your fix
F7|field|4|Up and down|ordered|Level 3
D1|deep|5|Follow a knock|has_bp|Level 1
D2|deep|6|Drift and repair|ordered|Level 3, after your card arrives
D3|deep|5|Two files, one truth|joined central|Level 2
D4|deep|5|What is in your highstate?|ordered central|Level 3
D5|deep|6|Ticket 104: already fixed?|joined|Level 2
X1|deep|4|The other fault|fixed|Level 4, after your fix'

meta(){ printf '%s\n' "$QUESTS" | awk -F'|' -v id="$1" 'toupper($1)==toupper(id)'; }
is_open(){ local needs f; needs=$(meta "$1" | cut -d'|' -f5); for f in $needs; do "$f" || return 1; done; }
hq_only(){ solo_on && meta "$1" | cut -d'|' -f5 | grep -qw central; }   # a quest about what only Uyuni writes
HQ_ONLY="is for the HQ table: only Uyuni writes what it reads. Every other quest works with your own HQ."
title_of(){ if [ "$1" = R6 ] && solo_on; then echo "Two jobs, one machine"; else meta "$1" | cut -d'|' -f4; fi; }
QFP=""                                             # R4 only: the PUBLIC fingerprint tail (xx:xx), for HQ's cross-check
# The first solve tells the game {id, tier[, public fp]} (≤ 4 s); the [game] line prints only if the game took it.
done_mark(){ mkdir -p "$QD"; [ -e "$QD/$1.done" ] && return 0; touch "$QD/$1.done"
             if game_post_sync quest "{\"id\":\"$1\",\"tier\":\"$(meta "$1" | cut -d'|' -f2)\"${QFP:+,\"fp\":\"$QFP\"}}"; then
               printf '%s[game] Counted for the room (anonymous).%s\n\n' "$C" "$N"; fi; }
win(){ printf '\n%s  *** SIDE QUEST %s SOLVED ***%s\n' "$G" "$1" "$N"; shift; printf '  %s\n' "$@"; echo; done_mark "$Q"; exit 0; }
nope(){ printf '  %s\n' "$@" "Try as often as you like."; exit 1; }

list(){
  echo "${C}GEEKO CORP · SIDE QUESTS${N}   (optional · never ranked · your answers stay here)"
  local tier
  for tier in recon field deep; do
    echo; case $tier in recon) echo "RECON · one command, one answer";; field) echo "FIELD · two or three commands, one idea";;
                         deep) echo "DEEP · for crews who know Linux already";; esac
    printf '%s\n' "$QUESTS" | while IFS='|' read -r id t mins title needs where; do
      [ "$t" = "$tier" ] || continue
      if [ -e "$QD/$id.done" ]; then st="${G}solved${N}"
      elif hq_only "$id"; then st="for the HQ table"
      elif is_open "$id"; then st="${Y}open${N}  ->  quest.sh show $id"
      else st="opens at $where"; fi
      [ "$id" = R6 ] && title=$(title_of R6)
      printf '  %-3s %-30s ~%s min   %s\n' "$id" "$title" "$mins" "$st"
    done
  done
  echo; echo "Waiting for the room? Side quests: optional, never ranked."
  echo "Helping a neighbour counts more than any quest. - Mentari"
}

show(){
  local id; id=$(printf '%s' "$1" | tr 'a-z' 'A-Z')
  [ -n "$(meta "$id")" ] || { echo "No quest called $1. Type: /root/osas26/quest.sh"; exit 1; }
  hq_only "$id" && { echo "$id $HQ_ONLY"; exit 0; }
  is_open "$id" || { echo "$id opens at $(meta "$id" | cut -d'|' -f6). Nothing is missed: it waits for you."; exit 0; }
  printf '%s%s · %s%s   (%s · about %s min)\n\n' "$C" "$id" "$(title_of "$id" | tr 'a-z' 'A-Z')" "$N" \
         "$(meta "$id" | cut -d'|' -f2)" "$(meta "$id" | cut -d'|' -f3)"
  case $id in
  R1) cat <<'EOF'
HQ's Salt door has two numbers. The blueprint gives each number a name.
Run:
  grep -A14 '^  name: salt$' ~/uyuni.yaml | grep -E 'name:|port:'
Question: what is door 4505 called?
Answer:   /root/osas26/quest.sh answer R1 <name>
EOF
  ;;
  R2) cat <<'EOF'
HQ keeps its memory on volumes (disks). Some belong to Salt, the tool that carries HQ's orders.
Run:
  grep -A2 '^kind: PersistentVolumeClaim' ~/uyuni.yaml | grep -o 'name: [a-z0-9-]*salt[a-z0-9-]*'
Question: how many of HQ's volumes have "salt" in their name?
Answer:   /root/osas26/quest.sh answer R2 <number>
EOF
  ;;
  R3) cat <<'EOF'
When your sandbox joined, it showed HQ a ticket: the activation key.
Your machine keeps that ticket as a "grain": a fact it tells HQ about itself.
Run:
  venv-salt-call --local grains.get susemanager:activation_key
Question: which activation key did your machine show HQ?
Answer:   /root/osas26/quest.sh answer R3 <key>
EOF
  ;;
  R4) cat <<'EOF'
Your machine's ID card is its Salt key. It has two halves.
Run:
  ls /etc/venv-salt-minion/pki/minion/
  venv-salt-call --local key.finger
minion.pem is the secret half. minion.pub is the public half.
The fingerprint is a short code made from the public half.
Question: what are the LAST TWO PAIRS of your fingerprint? (like 4f:9c)
Answer:   /root/osas26/quest.sh answer R4 <xx:xx>
EOF
  ;;
  R5) solo_on && echo "Your own HQ: HQ below is YOUR master, and its yes was YOUR salt-key -a."
      cat <<'EOF'
Before HQ said yes, your minion knocked and waited. Its diary (the log) remembers.
Run:
  grep 'cached the public key' /var/log/venv-salt-minion.log | tail -n 2
The line says ERROR, but read its words: is anything really broken?
Question: how many seconds did your minion wait between knocks?
Answer:   /root/osas26/quest.sh answer R5 <seconds>
EOF
  grep -q 'cached the public key' "$LOG" 2>/dev/null || cat <<'EOF'
(No line in your diary? HQ said yes before your minion had to wait.
 The real line from our test machine:
 [ERROR   ] The Salt Master has cached the public key for this node, this salt minion will wait
 for 10 seconds before attempting to re-authenticate)
EOF
  ;;
  R6) if solo_on; then cat <<'EOF'
Today your sandbox has TWO jobs: master AND minion. The master opens doors; the minion dials them.
Run:
  ss -tln | grep -E ':450[56]'
  ss -tn | grep -E ':450[56]'
The LISTEN lines are your master's doors, on 127.0.0.1 only: nobody outside can knock.
In each ESTAB line: the first address:port is one end, the second the other end.
Question: in the minion's line to :4505, what is the MINION's own port number?
Answer:   /root/osas26/quest.sh answer R6 <number>
EOF
      else cat <<'EOF'
Does your sandbox have an open door for Salt? And who dialled the two lines to HQ?
Run:
  ss -tln | grep -E ':450[56]' || echo 'no Salt doors open on this machine'
  ss -tn | grep -E ':450[56]'
In each line: YOUR address:port comes first, HQ's address:port second.
Question: in the line that ends with :4505, what is YOUR side's port number?
Answer:   /root/osas26/quest.sh answer R6 <number>
EOF
      fi
  ;;
  R7) solo_on && echo "Your own HQ: HQ below is YOUR master; its [HQ] message was the yellow [YOUR HQ] one."
      cat <<'EOF'
At Level 3, HQ sent your machine two kinds of orders. Your minion wrote each one in its diary.
Run:
  grep 'Executing command' /var/log/venv-salt-minion.log | tail -n 4
Question: which Salt function carried HQ's REMOTE COMMAND (the yellow [HQ] message)?
Answer:   /root/osas26/quest.sh answer R7 <function>
EOF
  grep -q 'Executing command' "$LOG" 2>/dev/null || cat <<'EOF'
(Nothing? Your minion's diary keeps only warnings today. The real lines from our test machine:
 [INFO    ] User ... Executing command state.apply with jid 20261003090530123456
 [INFO    ] User ... Executing command cmd.run with jid 20261003090601654321)
EOF
  ;;
  F1) cat <<'EOF'
At Level 2, HQ keeps a copy of your machine's ID card in its folder /etc/salt.
A folder inside a program box is lost when the box restarts, unless a VOLUME holds it.
Run:
  grep -A1 'mountPath: /etc/salt$' ~/uyuni.yaml
Question: which volume keeps HQ's /etc/salt safe?
Answer:   /root/osas26/quest.sh answer F1 <volume>
EOF
  ;;
  F2) cat <<'EOF'
Your crew card lives on YOUR disk: /etc/motd.
Its recipe (the state channel osas26-welcome) lives at HQ, in the folder /srv/susemanager/salt.
(Your own HQ keeps its copy in /srv/salt/manager_org_1. The question is about Uyuni HQ.)
Run:
  grep -A1 'mountPath: /srv/susemanager$' ~/uyuni.yaml
Question: which HQ volume keeps the recipe?
Answer:   /root/osas26/quest.sh answer F2 <volume>
EOF
  ;;
  F3) cat <<'EOF'
HQ checked your machine's ID card. Did your machine check HQ's?
Run:
  ls /etc/venv-salt-minion/pki/minion/minion_master.pub
  venv-salt-call --local key.finger_master
Question: the last two pairs of HQ's fingerprint, as YOUR machine remembers it?
(Then compare with HQ's ID card on the big screen.)
Answer:   /root/osas26/quest.sh answer F3 <xx:xx>
EOF
      solo_on && echo "Your own HQ: HQ is YOUR master. Its ID card, as the master itself shows it: salt-key -f master.pub"
  ;;
  F4) cat <<'EOF'
HQ knows your machine by two names. One you chose. One join.sh made fresh (step 2 of 4).
Run:
  venv-salt-call --local grains.item id machine_id
Question: what are the first 4 characters of your machine_id? Then compare with a neighbour's.
Answer:   /root/osas26/quest.sh answer F4 <4 characters>
EOF
  ;;
  F5) cat <<EOF
HQ did not send you a finished card. It sent a RECIPE, and your machine filled it in.
Run (it downloads the recipe from HQ, over door 4506):
  venv-salt-call cp.get_file_str salt://manager_org_$(org)/osas26-welcome/init.sls | grep -n 'file_exists\|b_blueprint ='
Question: which file on YOUR machine does the recipe check for your Blueprint box?
Answer:   /root/osas26/quest.sh answer F5 <path>
EOF
  ;;
  F6) cat <<'EOF'
While your machine was dark, the minion wrote what went wrong. In plain words.
Run:
  grep ERROR /var/log/venv-salt-minion.log | tail -n 3
Question: which word in those lines names your fault?
Answer:   /root/osas26/quest.sh answer F6 <word>
EOF
  ;;
  F7) cat <<'EOF'
Two kinds of facts travel between your machine and HQ.
UP: grains are facts your machine tells HQ.       DOWN: pillar is data HQ gives your machine.
Run:
  venv-salt-call --local grains.get os
  venv-salt-call pillar.get org_id
(pillar holds secrets too: never print ALL of it on a projector. Ask for one item, like here.)
Question: what is your org_id, the organisation number HQ gave you?
Answer:   /root/osas26/quest.sh answer F7 <number>
EOF
      solo_on && echo "Your own HQ gives it from a file you can read: cat /srv/pillar/osas26.sls"
  ;;
  D1) cat <<'EOF'
At Level 2 your sandbox knocks on HQ's door 4506.
Inside HQ, the receptionist (Traefik) catches the knock at an "entry point"
and routes it to a Service. Follow the knock through the blueprint.
Run:
  grep -A16 'name: salt-request-route' ~/uyuni.yaml | grep -A1 -E 'entryPoints|services'
Question: which entry point catches your knock?
Answer:   /root/osas26/quest.sh answer D1 <entry point>
EOF
  ;;
  D2) o=$(org); cat <<EOF
A state is a rule. A highstate makes it true again. Prove it on your own card.
First type:  /root/osas26/quest.sh start D2
Then:
 1 Break your card on purpose:
     echo ' ORDER FROM HQ: take the night off' >> /etc/motd
 2 Ask Salt what it WOULD change (test mode changes nothing):
     venv-salt-call state.apply manager_org_$o.osas26-welcome test=True
   Look for "Result: None" and the line with a minus sign.
 3 Make it so:
     venv-salt-call state.apply manager_org_$o.osas26-welcome
 4 Run step 3 again. What changed the second time?
Check:  /root/osas26/quest.sh check D2
EOF
  ;;
  D3) cat <<'EOF'
Your minion reads EVERY file in its folder minion.d, in alphabetical order.
When two files disagree, the last one wins.
Run:
  ls /etc/venv-salt-minion/minion.d/
  grep -H '^master' /etc/venv-salt-minion/minion.d/*.conf
  venv-salt-call --local config.get master
Read the first line of each file too:  head -n 1 /etc/venv-salt-minion/minion.d/*.conf
Question: which file wins when two files say different things? (And who wrote that file?)
Answer:   /root/osas26/quest.sh answer D3 <file name>
EOF
  ;;
  D4) cat <<'EOF'
A highstate applies a LIST of states: the top file. HQ builds your machine's list.
Run:
  venv-salt-call state.show_top
Question: which item in the list brings your crew card?
(Hint: HQ gave the state channel to your machine itself, through the activation key.)
Answer:   /root/osas26/quest.sh answer D4 <item>
EOF
  ;;
  D5) cat <<'EOF'
HQ ticket 104. The 2026.8.0 chart has a small typo in a comment. Is it already fixed?
Run:
  helm show values oci://registry.opensuse.org/uyuni/server-helm --version 2026.8.0 | grep -n 'tab will'
  curl -s https://raw.githubusercontent.com/uyuni-project/uyuni/master/containers/server-helm/values.yaml | grep -n 'By default the ta'
Question: on master, which word replaced "tab"?
Lesson for real bug hunters: always check the newest version first.
Answer:   /root/osas26/quest.sh answer D5 <word>
EOF
  ;;
  X1) mine=$(fault_mode); other=$([ "$mine" = dns ] && echo port || echo dns)
      cat <<EOF
Your machine had the ${mine:-?} fault. Other crews had the other one.
Here is the REAL diary of the other fault (captured on our test machine with Salt 3006.9):

EOF
      if [ "$other" = dns ]; then printf '%s\n' "$X1_DNS_LOG"; else printf '%s\n' "$X1_PORT_LOG"; fi
      cat <<'EOF'

Nothing to run: read the words, not only the level.
Runbook: 1 config -> 2 DNS -> 3 port -> 4 log -> 5 restart the minion.
Question: which runbook step (a number) finds THIS fault?
Answer:   /root/osas26/quest.sh answer X1 <step number>
EOF
  ;;
  esac
}

answer(){
  Q=$(printf '%s' "$1" | tr 'a-z' 'A-Z'); shift
  [ -n "$(meta "$Q")" ] || { echo "No quest called $Q. Type: /root/osas26/quest.sh"; exit 1; }
  hq_only "$Q" && { echo "$Q $HQ_ONLY"; exit 0; }
  is_open "$Q" || { echo "$Q opens at $(meta "$Q" | cut -d'|' -f6)."; exit 0; }
  local a h live
  a=$(norm "$*"); h=$(hash_of "$a")
  [ -n "$a" ] || { echo "Usage: /root/osas26/quest.sh answer $Q <your answer>"; exit 1; }
  case $Q in
  R1) case $h in
      a5d47a4311d759db69e576d9eedd6a02fcfd9cd214129fa8492ee1e9c7343def)
        win R1 "Yes: publish. On 4505 HQ PUBLISHES its orders to every minion at once." \
               "4506 is 'request': there your minion asks and answers (its ID card, its results, files)." \
               "Your sandbox opens BOTH lines. HQ talks back down them." ;;
      1f58b9145b24d108d7ac38887338b3ea3229833b9c1e418250343f907bfd1047)
        nope "That is door 4506's name. Which name sits next to port 4505?" ;;
      esac; nope "Not this one. Look for the line 'name:' right above 'port: 4505'." ;;
  R2) [ "$h" = 4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a ] && \
        win R2 "Four: etc-salt (settings and keys), srv-salt (recipes), var-salt (work files)," \
               "run-salt-master (the running master). If HQ's program restarts, the disks stay." \
               "That is why Kubernetes needs VOLUMES: they are HQ's memory."
      nope "Count the lines the command printed. Each line is one volume." ;;
  R3) case $h in
      349e23550518c2f065fa8618157efd4d324f782e95f72228ad3c0fd1a628d60d)
        solo_on && win R3 "Right: 1-osas26-fleet. Uyuni reads this ticket: team osas26-fleet, and its rules." \
               "Your own HQ is plain Salt: it ignores tickets. Anyone can TYPE a ticket anyway." \
               "Who you are is your Salt key (the ID card), and YOU accepted it with salt-key -a. Try R4 next."
        win R3 "Right: 1-osas26-fleet. It told HQ: put me in team osas26-fleet, give me its rules." \
               "But anyone can TYPE a ticket. So the ticket says the team, not who you are." \
               "Who you are is your Salt key (the ID card). HQ had to accept THAT. Try R4 next." ;;
      57b2db17692859f1a8be14b721e2ac8990a6e20d7af2bfc1c2d62cd8d9fca774)
        nope "That is the TEAM (system group) the key put you in. The key itself starts with a number." ;;
      esac; nope "Not this one. Copy the value under 'local:'." ;;
  R4) live=$(timeout 20 "$SALT" --local key.finger 2>/dev/null | first | awk -F: '{print $(NF-1)":"$NF}')
      [ -n "$live" ] || nope "Your machine did not answer. Is the Salt bundle installed? (join.sh)"
      if [ "$(printf '%s' "$a" | tr -d ':')" = "$(printf '%s' "$live" | tr -d ':')" ]; then
        # the tail is public (made from the public key): the game compares it with the key HQ really accepted
        solo_on && win R4 "Yes: $live. That code is made from your PUBLIC half (minion.pub). Safe to show anyone." \
               "The secret half (minion.pem) never leaves this machine." \
               "When YOU accepted it, your master saved exactly this code. See: salt-key -f $(tr -cd 'a-z0-9-' 2>/dev/null < "$ID_FILE")"
        [[ $live =~ ^[0-9a-f]{2}:[0-9a-f]{2}$ ]] && QFP=$live
        win R4 "Yes: $live. That code is made from your PUBLIC half (minion.pub). Safe to show anyone." \
               "The secret half (minion.pem) never leaves this machine." \
               "When HQ accepted you, it accepted exactly this code. The game can check it for you: look at your game page."
      fi
      nope "Not the last two pairs of YOUR fingerprint. Run the command again and read its very end." ;;
  R5) [ "$h" = 4a44dc15364204a80fe80e9039455cc1608281820fe2b24f1e5233ade6af1dd5 ] && \
        win R5 "10 seconds. 'Cached the public key' means HQ HAS your key but has not said yes: PENDING." \
               "Your minion knocked again every 10 seconds until the doors opened." \
               "The log said ERROR, but nothing was broken. Read a log's words, not only its level."
      nope "Look for the words 'wait for ... seconds' in the line." ;;
  R6) live=$(ss -Htn state established '( dport = :4505 )' 2>/dev/null \
             | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/){n=split($i,p,":"); print p[n]; break}}')
      [ -n "$live" ] || nope "No line to 4505 right now. Is your machine dark? (Level 4 runbook)"
      for p in $live; do [ "$a" = "$p" ] && solo_on && win R6 "Yes: $p. The minion picked that random 'from' number when it DIALLED door 4505." \
          "The caller picks a random number. The called side has the fixed door number." \
          "Your master listens (on 127.0.0.1 only); your minion calls. With Uyuni HQ, a sandbox has no doors at all."; done
      for p in $live; do [ "$a" = "$p" ] && win R6 "Yes: $p. Your machine picked that random 'from' number when it DIALLED door 4505." \
          "The caller picks a random number. The called side has the fixed door number." \
          "No Salt door is open here. Your sandbox called out; HQ answers down that line."; done
      nope "Not your side's number. In the :4505 line, YOUR address:port is the first one." ;;
  R7) case $h in
      bd680b4bcd6459a6e138d473124bdf07c48fb177fd0dcd7c84d34f779f112730)
        win R7 "cmd.run: 'run a shell command'. It came down your 4505 line as a job with a number (jid)," \
               "ran as ROOT, and your minion sent the answer back on 4506. A one-time shout." \
               "state.apply was the other order: the highstate that wrote your card. A rule." ;;
      84c950ff1476abfbeaecf67a0b74f611a863a82cca00cb31384d619597420d11)
        nope "state.apply carried the highstate (the STATE that wrote your card). Which one carried the command?" ;;
      esac; nope "Look at the words after 'Executing command'." ;;
  F1) [ "$h" = b074f018930274d9bc15ccbec69480814156fce446a06a787d2ba2b5dd5d1bce ] && \
        win F1 "Yes: etc-salt. Your machine's ID card lives on that disk at HQ." \
               "HQ's program can restart, and HQ still remembers that it trusts you." \
               "Where data lives: your card on YOUR disk, your key on HQ's etc-salt disk."
      nope "Read the line under 'mountPath: /etc/salt'." ;;
  F2) [ "$h" = 5341f4b2d1a32c9448ddb5e614dfa3220825c61cf5e35f604e046aae7c06122c ] && \
        win F2 "Yes: srv-susemanager. The RECIPE lives at HQ, the CARD lives on your machine." \
               "Change the recipe, and nothing happens until a highstate. (Remember 16:04?)"
      nope "Read the line under 'mountPath: /srv/susemanager'." ;;
  F3) live=$(timeout 20 "$SALT" --local key.finger_master 2>/dev/null | first | awk -F: '{print $(NF-1)":"$NF}')
      [ -n "$live" ] || nope "No HQ key saved yet. Has HQ accepted your machine?"
      if [ "$(printf '%s' "$a" | tr -d ':')" = "$(printf '%s' "$live" | tr -d ':')" ]; then
        if solo_on; then
          own=$(timeout 20 "${SALT_KEY:-salt-key}" -f master.pub 2>/dev/null | sed -n 's/^master.pub: *//p' | awk -F: '{print $(NF-1)":"$NF}')
          msg="Compare it with your master's own card: salt-key -f master.pub"
          [ -n "$own" ] && { [ "$own" = "$live" ] && msg="Same as your own master's ID card (salt-key -f master.pub): your minion talks to YOUR master." \
                                                || msg="Different from your master's own card! Call a helper: that is worth checking."; }
          win F3 "Yes: $live. $msg" \
                 "Your machine saved its master's public key the first time it connected: minion_master.pub." \
                 "A fake master with another key would be refused: 'The master key has changed ... subverted'. Trust goes both ways."
        fi
        hq=$(sed -n 's/^HQ_MASTER_FINGER_TAIL=//p' "$SERVER_ENV" 2>/dev/null)
        msg="Compare it with HQ's ID card on the big screen."
        [ -n "$hq" ] && { [ "$hq" = "$live" ] && msg="Same as HQ's real ID card: your machine talks to the real HQ." \
                                              || msg="Different from HQ's card on the screen! Call a helper: that is worth checking."; }
        win F3 "Yes: $live. $msg" \
               "Your machine saved HQ's public key the first time it connected: minion_master.pub." \
               "A fake HQ with another key would be refused: 'The master key has changed ... subverted'. Trust goes both ways."
      fi
      nope "Not the end of HQ's fingerprint as your machine stores it. Run key.finger_master again." ;;
  F4) live=$(timeout 20 "$SALT" --local grains.get machine_id 2>/dev/null | first | cut -c1-4)
      [ -n "$live" ] || nope "Your machine did not answer the grains question."
      [ "$a" = "$live" ] && solo_on && win F4 "Yes. Uyuni files each machine's personal recipe list under that number: custom_<machine_id>." \
          "Two sandboxes with the SAME machine-id would look like ONE machine to Uyuni." \
          "That is why join.sh made a fresh one. Your neighbour's starts differently, right?"
      [ "$a" = "$live" ] && win F4 "Yes. HQ files your personal recipe list under that number: custom_<machine_id>." \
          "Two sandboxes with the SAME machine-id would look like ONE machine to HQ." \
          "That is why join.sh made a fresh one. Your neighbour's starts differently, right?"
      nope "Not the first 4 characters of YOUR machine_id." ;;
  F5) case $a in /root/uyuni.yaml|uyuni.yaml|~/uyuni.yaml)
        win F5 "Yes: /root/uyuni.yaml, the blueprint you rendered at Level 1." \
               "Salt ran the recipe ON YOUR MACHINE, so it could look at your own files." \
               "That is why your card knew your Level 1. HQ sent the recipe; your machine cooked it." ;;
      esac; nope "Look for file_exists(...) next to b_blueprint." ;;
  F6) mode=$(tr -cd 'a-z' < "$BREAK_FILE" 2>/dev/null)
      case "$mode:$a" in
      dns:dns|dns:lookup|dns:notfound|dns:found)
        win F6 "Yes. 'DNS lookup ... failed' and 'not found': your machine could not turn HQ's NAME into a number." \
               "Runbook step 2. The diary said it in plain words." ;;
      port:timeout|port:timed|port:responding|port:authenticate|port:sign_in|port:signin)
        win F6 "Yes. 'Is master ... responding?' and 'timeout': your machine knew HQ's number but could not reach the door." \
               "Runbook step 3, the port. The diary said it in plain words." ;;
      esac; nope "Read the ERROR lines again. Which word says what failed? (Your fault was: ${mode:-unknown})" ;;
  F7) live=$(timeout 25 "$SALT" pillar.get org_id 2>/dev/null | first)
      if [ -n "$live" ]; then [ "$a" = "$live" ] && solo_on && win F7 "Yes: org_id $live came DOWN from your own HQ, in pillar (/srv/pillar/osas26.sls)." \
          "Grains go UP (your machine tells its master: I am Ubuntu). Pillar comes DOWN (the master tells your machine)." \
          "Pillar can hold secrets, so a master sends it only to the machine it belongs to. Uyuni does the same."
        [ "$a" = "$live" ] && win F7 "Yes: org_id $live came DOWN from HQ, in pillar." \
          "Grains go UP (your machine tells HQ: I am Ubuntu). Pillar comes DOWN (HQ tells your machine: you are in org $live)." \
          "Pillar can hold secrets, so it is sent only to the machine it belongs to."
        nope "Not your org_id. Look under 'local:'."
      else case $a in *[!0-9]*) nope "A number, please." ;; *) win F7 "(HQ did not answer the check right now; we trust your eyes.)" \
          "Grains go UP; pillar comes DOWN. Pillar is sent only to the machine it belongs to." ;; esac; fi ;;
  D1) [ "$h" = f57f7ea3c34dbc2ef21fbd34734e981592e478a27cdd07de856491be42bca948 ] && \
        win D1 "Yes: salt-request. Traefik catches your knock there and sends it to Service salt, port 4506." \
               "That Service is ClusterIP (inside-only): only the receptionist can reach it." \
               "The 8 lines on the slide open the salt-request entry point on HQ's machine."
      nope "Look under 'entryPoints:'." ;;
  D3) case $a in susemanager.conf|susemanager)
        win D3 "Yes: susemanager.conf sorts after osas26.conf, so it wins." \
               "HQ WROTE it (look at its first line) when your machine registered: HQ manages Salt's own settings too." \
               "Real lesson: ask the machine what it really uses (config.get), not only one file." ;;
      esac; nope "Which file name comes LAST in alphabetical order?" ;;
  D4) case $h in
      6cdfd271da635d491e37a2b4a1044b306e6e9e039aeadee95bb355efadf8cb33)
        win D4 "Yes: custom. It includes custom_<your machine_id>, which includes manager_org_1.osas26-welcome," \
               "the state channel your activation key gave you. The other items are HQ's own chores:" \
               "certificates, channels, packages, and even Salt's own settings (services.salt-minion)." ;;
      e0ad0bb8c21e8b92e6030570069badee02e2a0bb554468a829d511ffa51f3a09)
        nope "custom_groups is for channels given to a whole GROUP. Yours was given to your machine itself." ;;
      esac; nope "One word from the list. Which one sounds like YOUR machine's own states?" ;;
  D5) [ "$h" = 2a1073a6e67f0e5f09a5957c659503c690efe7272be8313df872556a9a684d8c ] && \
        win D5 "Yes: tag. Someone fixed it on master (PR #12346) after 2026.8.0 was released." \
               "Real bug hunters check the newest version first, then search for duplicates. You did step one."
      nope "Compare the two lines. Which word is different?" ;;
  X1) mine=$(fault_mode)
      case "$mine:$h" in
      port:d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35)
        win X1 "Yes: step 2, DNS. 'DNS lookup ... failed' and 'not found': that machine could not turn HQ's NAME into a number." \
               "Your fault was the port: the name was fine, the door was not. Two faults, two diary lines, two runbook steps." ;;
      dns:4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce)
        win X1 "Yes: step 3, the port. 'Is master ... responding?' and 'timeout': the name was fine, the door was not." \
               "Your fault was DNS: the name itself failed. Two faults, two diary lines, two runbook steps." ;;
      dns:d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35|port:4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce)
        nope "That step found YOUR fault. This diary shows the other one: read its words again." ;;
      *:4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a)
        nope "Step 4, the log, is where you READ this diary. Which earlier step would find the fault itself?" ;;
      esac; nope "One number from 1 to 5. Which step checks what the diary complains about?" ;;
  D2) echo "D2 is checked with: /root/osas26/quest.sh check D2"; exit 0 ;;
  esac
}

start_d2(){
  ordered || { echo "D2 opens after HQ's order reaches your card (Level 3)."; exit 0; }
  healthy || { echo "Your machine cannot reach HQ right now. Bring it back first (Level 4 runbook)."; exit 0; }
  mkdir -p "$QD"; date +%s > "$QD/D2.start"; cp "$MOTD" "$QD/D2.motd.before" 2>/dev/null
  echo "D2 started. Now do steps 1 to 4 from: /root/osas26/quest.sh show D2"
}
check_d2(){
  [ -s "$QD/D2.start" ] || { echo "First: /root/osas26/quest.sh start D2"; exit 1; }
  Q=D2
  if grep -q 'take the night off' "$MOTD"; then
    nope "Your card still says 'take the night off'. Step 3 makes it so. (Or wait: the promotion highstate repairs it too!)"; fi
  local m s; m=$(stat -c %Y "$MOTD" 2>/dev/null || stat -f %m "$MOTD"); s=$(cat "$QD/D2.start")
  [ "$m" -ge "$s" ] || nope "Your card was not written again since you started. Do steps 1 to 3."
  grep -qF 'ORDER FROM HQ:' "$MOTD" || nope "Your card lost its ORDER line. Run step 3 again."
  solo_on && win D2 "Repaired. Test mode showed 'Result: None': Salt told you the plan and changed nothing." \
         "Then the state made the card true again. The second run changed nothing: that is a RULE, not a shout." \
         "A hand edit survives only until the next state.apply. On Uyuni HQ, its promotions do it for every machine."
  win D2 "Repaired. Test mode showed 'Result: None': Salt told you the plan and changed nothing." \
         "Then the state made the card true again. The second run changed nothing: that is a RULE, not a shout." \
         "A hand edit survives only until the next highstate. HQ's promotions at 16:23 do the same for everyone."
}

case "${1:-}" in
  ''|list) list ;;
  show)   show "${2:-}" ;;
  answer) [ $# -ge 3 ] || { echo "Usage: /root/osas26/quest.sh answer <ID> <your answer>"; exit 1; }; shift; answer "$@" ;;
  start)  [ "$(printf '%s' "${2:-}" | tr 'a-z' 'A-Z')" = D2 ] && start_d2 || echo "Only D2 has a start step." ;;
  check)  [ "$(printf '%s' "${2:-}" | tr 'a-z' 'A-Z')" = D2 ] && check_d2 || echo "Only D2 has a check step. Others: quest.sh answer <ID> <answer>" ;;
  *) echo "usage: quest.sh [list] | show ID | answer ID WORD | start D2 | check D2" ;;
esac
