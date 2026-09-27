#!/usr/bin/env bash
# lab/runner/hq-table.sh setup CAP | guard | status - RUNNER-HQ v7: the HQ TABLE's cap. The speaker's own sandbox plus
# up to 7 front-table crews join this HQ through bore.pub:4505/4506 with `join.sh --hq` (CAP 8); every other sandbox runs
# its own HQ (MODE=solo). Run as root on HQ.
#   setup CAP   /etc/osas26/cap; the accept timer's loop (osas26-accept.service, 15:55 WIB, whose unit file says 60)
#               and a manual go-accept both get CAP (a drop-in, and CAP in root's shell); starts the guard
#   guard       (systemd: osas26-hqtable-guard) every 3 s, while an accept loop runs: once HQ already trusts CAP attendee
#               machines (ids ^osas26-<crew>-<hex3>$, the accept loop's own rule), every FURTHER pending attendee key
#               is REJECTED. The accept loop only counts and ignores; the guard makes the "no" explicit, so the minion
#               is told at once (Salt 3006: "The Salt Master has rejected this minion's public key", and it stops)
#               instead of waiting in the pending list. The sandbox's answer is its own HQ: `join.sh --solo`.
#               leap-a, leap-b and any other id are never touched; nothing is ever deleted or accepted here.
#   status      CAP, accepted attendee keys, and every refusal so far (/root/osas26/hq-table.log)
set -uo pipefail
RX='^osas26-[a-z0-9]{2,12}-[0-9a-f]{3}$'
W=/root/osas26; L=$W/hq-table.log; export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
PATH=$PATH:/var/lib/rancher/rke2/bin
k(){ timeout 20 kubectl -n uyuni exec deploy/uyuni -c uyuni -- "$@"; }
cap(){ tr -cd 0-9 < /etc/osas26/cap 2>/dev/null; }
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
case ${1:-} in
  setup)
    c=${2:?CAP}; [[ $c =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le 99 ] || { echo "CAP 1-99" >&2; exit 2; }
    install -d -m 0755 /etc/osas26 /etc/systemd/system/osas26-accept.service.d; echo "$c" > /etc/osas26/cap
    printf '[Service]\n# RUNNER-HQ v7 (lab/runner/hq-table.sh): the HQ table, not the room\nEnvironment=CAP=%s\n' "$c" \
      > /etc/systemd/system/osas26-accept.service.d/10-hq-table-cap.conf
    grep -q '^export CAP=' /root/.bashrc 2>/dev/null && sed -i "s/^export CAP=.*/export CAP=$c   # the HQ table (hq-table.sh)/" /root/.bashrc \
      || echo "export CAP=$c   # the HQ table (hq-table.sh)" >> /root/.bashrc
    install -m 0755 "$(readlink -f "$0")" /usr/local/sbin/osas26-hqtable
    cat > /etc/systemd/system/osas26-hqtable-guard.service <<'EOF'
[Unit]
Description=oSAS26 RUNNER-HQ: the HQ table's CAP guard (rejects attendee keys beyond CAP while an accept loop runs)
[Service]
Type=simple
ExecStart=/usr/local/sbin/osas26-hqtable guard
Restart=always
RestartSec=5
EOF
    systemctl daemon-reload && systemctl enable --now osas26-hqtable-guard.service
    echo "HQ table: CAP $c (accept timer drop-in, go-accept, guard $(systemctl is-active osas26-hqtable-guard))" ;;
  guard)
    while :; do
      if systemctl is-active --quiet osas26-accept.service osas26-accept-manual.service 2>/dev/null; then   # any of them
        c=$(cap); keys=$(k salt-key --out=json 2>/dev/null) || { sleep 3; continue; }
        acc=$(jq -r '.minions[]' <<<"$keys" | grep -cE "$RX" || true)
        if [ -n "$c" ] && [ "$acc" -ge "$c" ]; then
          for id in $(jq -r '.minions_pre[]' <<<"$keys" | grep -E "$RX" || true); do
            k salt-key -y -r "$id" >/dev/null 2>&1 && echo "$(date -u +%FT%TZ) refused $id (the HQ table is full: $acc of CAP $c): its own HQ is the answer (join.sh --solo)" | tee -a "$L"
          done
        fi
      fi
      sleep "${GUARD_EVERY:-3}"
    done ;;
  status)
    echo "CAP $(cap) · guard $(systemctl is-active osas26-hqtable-guard 2>/dev/null) · accept loop: timer $(systemctl is-active osas26-accept.timer 2>/dev/null), timer run $(systemctl is-active osas26-accept.service 2>/dev/null), manual $(systemctl is-active osas26-accept-manual.service 2>/dev/null)"
    keys=$(k salt-key --out=json 2>/dev/null)
    echo "attendee keys: accepted $(jq -r '.minions[]' <<<"$keys" | grep -cE "$RX") · pending $(jq -r '.minions_pre[]' <<<"$keys" | grep -cE "$RX") · refused $(jq -r '.minions_rejected[]' <<<"$keys" | grep -cE "$RX")"
    [ -s "$L" ] && tail -n 20 "$L" || echo "no refusals" ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
