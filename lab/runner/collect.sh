#!/usr/bin/env bash
# lab/runner/collect.sh OUTDIR - RUNNER-HQ: copy the run's evidence (logs, timings, facts; NO secrets) to OUTDIR for the
# artifact upload, then refuse to leave anything that contains a secret value (PLAN §5.0's cast check: grep -F -f).
# Never copied: secrets.env, secrets-values.yaml, game.hdr, game.env, *.kubeconfig, rke2.yaml, the uyuni-charts tree.
set -uo pipefail
OUT=${1:?outdir}; W=/root/osas26; install -d "$OUT"
for f in build.log build-phases.tsv timings.tsv check.txt lab.env relay.env cf.env server.env rke2-version.txt \
         case1-noclass.txt case1-nopod.txt game-post.log accept-*.log e2e-*.log leaps.log leaps.state leaps.state.b \
         hq-table.log; do
  for g in $W/$f; do [ -f "$g" ] && cp "$g" "$OUT/"; done
done
[ -d $W/runner ] && cp -r $W/runner "$OUT/runner"
# v7: the doors as the Mac saw them, and the publisher's log (artifact names and states only)
bash "$(dirname "$(readlink -f "$0")")/doors.sh" env > "$OUT/doors.env" 2>/dev/null
cp /tmp/osas26-doors-publish.log "$OUT/runner/" 2>/dev/null
command -v podman >/dev/null && podman ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$OUT/runner/leaps-ps.txt" 2>/dev/null
[ -d /run/osas26-relay ] && { mkdir -p "$OUT/relay"; cp /run/osas26-relay/*.log /run/osas26-relay/*.port /run/osas26-relay/*.probe "$OUT/relay/" 2>/dev/null; }
[ -d /run/osas26-cf ] && { mkdir -p "$OUT/relay-cf"; cp /run/osas26-cf/*.log* /run/osas26-cf/*.host /run/osas26-cf/*.probe "$OUT/relay-cf/" 2>/dev/null; }
mkdir -p "$OUT/relay"; journalctl -u 'osas26-relay*' -u 'osas26-cf*' --no-pager -o short-iso > "$OUT/relay/journal.txt" 2>/dev/null || true
free -m > "$OUT/runner/free-end.txt" 2>/dev/null; df -h > "$OUT/runner/df-end.txt" 2>/dev/null
if command -v kubectl >/dev/null && [ -r /etc/rancher/rke2/rke2.yaml ]; then
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  { kubectl get nodes -o wide; kubectl get pods -A -o wide; kubectl top nodes; kubectl top pods -A; } > "$OUT/runner/k8s-end.txt" 2>&1
fi
# the secret check: every value of secrets.env (and the game token) must appear in NO collected file
S=$(mktemp); trap 'rm -f "$S"' EXIT; chmod 600 "$S"
[ -r $W/secrets.env ] && sed -n 's/^[A-Z_]*=//p' $W/secrets.env | grep -E '.{8,}' >> "$S"
[ -r $W/game.hdr ] && sed -n 's/^Authorization: Bearer //p' $W/game.hdr >> "$S"
if [ -s "$S" ] && grep -rlF -f "$S" "$OUT" >/dev/null 2>&1; then
  for f in $(grep -rlF -f "$S" "$OUT"); do echo "collect: a secret value appears in $(basename "$f"): removed"; rm -f "$f"; done
fi
chmod -R a+rX "$OUT"; du -sh "$OUT"; ls -R "$OUT" | head -50
