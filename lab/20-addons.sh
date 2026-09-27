#!/usr/bin/env bash
# 20-addons.sh (cp2, cp3) - PLAN §5.6: Helm 4.2.4, local-path v0.0.36 (+ the writer/reader smoke test), cert-manager
# v1.21.2 + trust-manager v0.24.0, and the two Case 1 event lines. SELinux labelling only on Leap 16 (guarded).
# Safe to re-run.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
lab_env; cd "$W"; M=$LAB/manifests
t addons_start
# Helm 4.2.4 - the same as the Mac and the sandboxes; sha verified 2026-09-23 [L10]
HV=v4.2.4; HS=c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3
if ! helm version --short 2>/dev/null | grep -q "^${HV}+"; then
  S=$(mktemp -d); curl -fsSL --retry 3 -o "$S/helm.tgz" "https://get.helm.sh/helm-${HV}-linux-amd64.tar.gz"
  echo "$HS  $S/helm.tgz" | sha256sum -c -
  tar -xzf "$S/helm.tgz" -C "$S" && install -m0755 "$S/linux-amd64/helm" /usr/local/bin/helm; rm -rf "$S"
fi
helm version --short
# local-path v0.0.36, digest-pinned, no default-class annotation (Akash's proven manifest) [L23]
mkdir -p /opt/local-path-provisioner
if [ "$OS" = leap16 ]; then                                        # SELinux label required [RKE2 §5]
  { semanage fcontext -a -t container_file_t '/opt/local-path-provisioner(/.*)?' 2>/dev/null || true; restorecon -R /opt/local-path-provisioner; } \
    || chcon -Rt container_file_t /opt/local-path-provisioner
fi
kubectl apply -f "$M/local-path-storage.yaml"
if kubectl get sc local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q true; then
  die "local-path is a DEFAULT StorageClass (the plan: none; Case 1 depends on it)"; fi
kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=5m
# smoke test: writer then reader on one PVC (RUNBOOK §7 manifests) [ASSETS §a.2]
kubectl delete pod storage-smoke storage-smoke-reader --ignore-not-found --wait=true >/dev/null
kubectl delete pvc storage-smoke --ignore-not-found --wait=true >/dev/null
STORAGE_CLASS=local-path envsubst < "$M/storage-smoke.yaml.tmpl" | kubectl apply -f -
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/storage-smoke --timeout=5m && kubectl delete pod storage-smoke
kubectl apply -f "$M/storage-smoke-reader.yaml"
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/storage-smoke-reader --timeout=5m
kubectl delete pod storage-smoke-reader && kubectl delete pvc storage-smoke
echo "storage smoke test: writer + reader Succeeded"
t storage_ok
# PKI (versions per D2) [L3]
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 \
  -n cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m
if ! helm upgrade --install trust-manager oci://quay.io/jetstack/charts/trust-manager --version v0.24.0 \
       -n cert-manager --wait --timeout 10m; then
  echo "trust-manager: the OCI tag failed; using the jetstack Helm repo"          # PLAN §5.6 ⚠️
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
  helm upgrade --install trust-manager jetstack/trust-manager --version v0.24.0 -n cert-manager --wait --timeout 10m
fi
helm -n cert-manager list
t pki_ok
# Case 1 ("The volume that never bound"): the two real event lines, saved for the slides, then deleted (CASE1=0 skips)
if [ "${CASE1:-1}" = 1 ]; then
  kubectl delete pvc case1-noclass case1-nopod --ignore-not-found --wait=true >/dev/null
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: case1-noclass, namespace: default}
spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 64Mi}}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: case1-nopod, namespace: default}
spec: {accessModes: [ReadWriteOnce], storageClassName: local-path, resources: {requests: {storage: 64Mi}}}
EOF
  sleep 20
  kubectl describe pvc case1-noclass > "$W/case1-noclass.txt"; kubectl describe pvc case1-nopod > "$W/case1-nopod.txt"
  tail -3 "$W/case1-noclass.txt"; tail -3 "$W/case1-nopod.txt"
  kubectl delete pvc case1-noclass case1-nopod
  t case1_captured
fi
