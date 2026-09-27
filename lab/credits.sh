#!/usr/bin/env bash
# credits.sh [BUGS_FOUND] - end credits for the shift (Quest's credits.sh in the Geeko Corp skin). READ-ONLY toward Uyuni/Salt.
# Crew = accepted attendee keys (nickname part only, alphabetical, de-duplicated): keys stay accepted after the
# sandboxes expire, so this works at 16:34. Extra lines (helpers WITH consent, organizers, and the twist's credits
# line, which must never sit in this public file): $D/credits-extra.txt.
# DOORPRIZE: cards are handed out in number order at the door, so the numbers in use are 1..N. N comes from $D/raffle-n
# (written off-projector in the admin session) or RAFFLE_N; 0 = no draw. Luck, not merit; seats without a laptop win
# too. (The game draws the same way, arisan-style, from the door helper's N; this is its terminal twin.)
# RED / Lean: runs on the Mac (bash 3.2, no kubectl, no jq) -> "everyone in Room 4":  BOARD_DIR=~/osas26-kit RAFFLE_N=<N> bash credits.sh 1
set -uo pipefail
ADM=/etc/rancher/rke2/rke2.yaml; D=${BOARD_DIR:-/root/osas26}
RX='^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$'
k(){ kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
if [ "${BOARD_FAKE:-}" = 1 ]; then k(){ cat "$D/fake-keys.json"; }; fi
bugs=${1:-1}
raffle=${RAFFLE_N:-$(cat "$D/raffle-n" 2>/dev/null || echo 0)}
names=$(k salt-key --out=json 2>/dev/null | jq -r '.minions[]' 2>/dev/null | grep -E "$RX" | cut -d- -f2 | sort -u)
n=$(printf '%s\n' "$names" | grep -c . || true)
ev=$(cat "$D/evidence-count" 2>/dev/null || echo 0)
W=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
delay=0.35; [ "$n" -gt 40 ] && delay=0.2; [ "$n" -gt 70 ] && delay=0.12; [ "${FAST:-}" = 1 ] && delay=0.08
line(){ printf '%*s\n' $(( (W + ${#1}) / 2 )) "$1"; sleep "$delay"; }
clear 2>/dev/null
[ "${BOARD_FAKE:-}" = 1 ] && line "*** REHEARSAL REPLAY: not live data ***"
for _ in 1 2 3 4 5 6; do line ""; done
line "G E E K O   C O R P"
line "your first SRE shift  ·  From Zero to Uyuni"
line "openSUSE.Asia Summit 2026  ·  Room 4  ·  Yogyakarta"
line ""; line ""
line "T H E   C R E W"
line ""
if [ "$n" -eq 0 ]; then line "everyone in Room 4"; else
  while read -r x; do [ -n "$x" ] && line "$x"; done <<<"$names"; fi
line ""
line "... and every field investigator with a paper case file"
line "Every name here worked today's shift."
line ""; line ""
line "SHIFT REPORT"
[ "$n" -gt 0 ] && line "crew nodes that joined HQ: $n"
[ "$ev" -gt 0 ] 2>/dev/null && line "crew nodes with sealed evidence: $ev"
line "discoveries today: $bugs"
line ""; line ""
if [ -s "$D/credits-extra.txt" ]; then
  while IFS= read -r x; do line "$x"; done < "$D/credits-extra.txt"; line ""; line ""; fi
line "HQ BUILT WITH"
line "openSUSE Leap 16  ·  RKE2  ·  Helm  ·  Salt  ·  Uyuni 2026.08"
line "Geeko Corp is not real, and not a SUSE or openSUSE product."
line "Uyuni and the server are real."   # the twist's own credits line lives in golden's credits-extra.txt (not public)
line ""; line ""
if [ "$raffle" -gt 3 ]; then
  drawn=$(awk -v n="$raffle" 'BEGIN { srand(); while (c < 3) { r = int(rand() * n) + 1; if (!(r in s)) { s[r] = 1; c++; printf "%s%02d", (c > 1 ? "  ·  " : ""), r } } }')
  line "DOORPRIZE"; line "$drawn"; line "(look at the number on your crew card)"; line ""; line ""; fi
line "Have a lot of fun..."
for _ in 1 2 3 4 5 6; do line ""; done
line "S H I F T   O V E R .   C O N T I N U E ?"
