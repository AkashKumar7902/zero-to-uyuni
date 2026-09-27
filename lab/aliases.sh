# shellcheck shell=bash disable=SC2139
# lab/aliases.sh - PLAN §5.8. Sourced from /root/.bashrc (40-harden.sh); nothing is exported, so the admin session
# never inherits the stage kubeconfig. The aliases expand their paths when defined, on purpose (SC2139).
command -v kubectl >/dev/null 2>&1 || PATH=$PATH:/var/lib/rancher/rke2/bin
L=/root/zero-to-uyuni/lab; ADM=/etc/rancher/rke2/rke2.yaml; STG=/root/osas26/stage.kubeconfig
# window "stage" (projected) - read-only kubeconfig, per alias
alias d-nodes="kubectl --kubeconfig=$STG get nodes -o wide"
alias d-pods="kubectl --kubeconfig=$STG -n uyuni get deploy,pods"
alias d-pvc-count="kubectl --kubeconfig=$STG -n uyuni get pvc -o custom-columns=CLASS:.spec.storageClassName,STATUS:.status.phase --no-headers | sort | uniq -c"   # counts only, NO names
alias d-pvc="kubectl --kubeconfig=$STG -n uyuni get pvc -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,STATUS:.status.phase | sort"   # names: admin/debug only; never projected before 16:28 (§4A.7)
alias d-routes="kubectl --kubeconfig=$STG -n uyuni get ingress,ingressroutetcp"
alias d-events="kubectl --kubeconfig=$STG get events -A --sort-by=.lastTimestamp | tail -15"
# window "board" (projected; root kubeconfig, safe commands only; each Salt alias below = ONE job: never loop them)
alias d-board="watch -n5 -t $L/board.sh"
alias d-ping="kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- salt 'osas26-*' test.ping -t 5 --out=txt | sort"
alias d-highstate="kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- salt 'osas26-*' state.apply -t 90 --out=txt | tail -20"   # fallback only
alias d-roster="$L/outage.sh roster"      # 16:15:30, before "Go" (golden's drill timer runs it; this is the manual fallback)
alias d-outage="$L/outage.sh"             # 16:18:30, 16:20:30, 16:22:30
alias d-evidence="$L/evidence.sh"         # once, ~16:25:30 (counts only)
alias d-credits="$L/credits.sh"           # 16:33, read-only; the raffle reads /root/osas26/raffle-n; FAST=1 d-credits under CL5
alias d-window="/usr/local/sbin/osas26-salt-window status"   # the host guard + the Salt window (FREE-GOLDEN §6.5)
# live official bootstrap on leap-b: the FQDN is expanded HERE, never on leap-b; 'leap-b' resolves via /root/.ssh/config (§5.9)
alias d-bootstrap-leapb='. /root/osas26/lab.env; ssh leap-b "curl -Sks https://${FQDN}/pub/bootstrap/bootstrap-osas26.sh | bash; venv-salt-call --local key.finger"'
# session "admin" (laptop panel only) - go-accept does not depend on the timer unit at all
alias go-accept="systemctl stop osas26-accept.service 2>/dev/null; systemd-run --unit=osas26-accept-manual -p RuntimeMaxSec=70min -E CAP=\${CAP:-60} /usr/local/sbin/osas26-accept-loop 65"
# d-savecounts <online-at-15:34:30> <HQ-desk-sealed>: record the show's counts BEFORE cleanup.sh (cleanup.sh refuses otherwise)
d-savecounts(){ local ON=${1:-?} DESK=${2:-?} D=/root/osas26 f; f=/root/osas26/counts-$(date +%F).txt
  { date -u +%FT%TZ
    echo "online at 15:34:30 (fingers 1): $ON   HQ desk sealed (SEALED stickers): $DESK"
    echo "crew on shift (accepted keys): $(kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- salt-key --out=json | jq -r '.minions[]' | grep -cE '^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$')"
    echo "registered: $(cat $D/.registered 2>/dev/null)   roster at Go: $(grep -c . $D/outage-roster 2>/dev/null)"
    echo "evidence sealed: $(cat $D/evidence-count 2>/dev/null)   outage: $(cat $D/room-status 2>/dev/null)"; } | tee "$f" && touch $D/counts-saved; }
d-reject(){ kubectl --kubeconfig=$ADM -n uyuni exec deploy/uyuni -c uyuni -- salt-key -y -d "$1"; echo "now delete system $1 in the UI (or run cleanup.sh)"; }
# golden-only finale aliases (they NAME the volume): scp'd to /root/osas26, never in the repo before Oct 3 evening (§4A.7)
if [ -f /root/osas26/finale-aliases.sh ]; then
. /root/osas26/finale-aliases.sh
fi
# v6: the game's admin aliases (d-game-on/off/status, d-drill-arm/plan, d-game-ping), once the hooks are installed (§5.16.3)
if [ -f /usr/local/share/osas26/aliases-game.sh ]; then
. /usr/local/share/osas26/aliases-game.sh
fi
