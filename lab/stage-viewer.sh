#!/usr/bin/env bash
# stage-viewer.sh - PLAN §5.8 step 2: the read-only kubeconfig for the PROJECTED "stage" window [CF §6.3 Stage 7].
# ServiceAccount default/stage-viewer = the built-in `view` role (no Secrets) + read on the Traefik and helm.cattle.io
# CRDs (`view` does not aggregate them). Writes /root/osas26/stage.kubeconfig (0600) and asserts BOTH sides: the token
# works (whoami, pods yes) AND it cannot read Secrets. Called by 40-harden.sh; safe to re-run.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
SKC=$W/stage.kubeconfig
kubectl create sa stage-viewer -n default --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding stage-viewer --clusterrole=view --serviceaccount=default:stage-viewer --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: stage-viewer-traefik}
rules: [{apiGroups: ["traefik.io","traefik.containo.us","helm.cattle.io"], resources: ["*"], verbs: ["get","list","watch"]}]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: stage-viewer-traefik}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: stage-viewer-traefik}
subjects: [{kind: ServiceAccount, name: stage-viewer, namespace: default}]
---
apiVersion: v1
kind: Secret
metadata: {name: stage-viewer-token, namespace: default, annotations: {kubernetes.io/service-account.name: stage-viewer}}
type: kubernetes.io/service-account-token
EOF
TOKEN=""; for _ in $(seq 30); do   # the token controller fills the Secret asynchronously; never build a credential-less kubeconfig
  TOKEN=$(kubectl -n default get secret stage-viewer-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d); [ -n "$TOKEN" ] && break; sleep 2; done
[ -n "$TOKEN" ] || die 'stage-viewer token never populated'
umask 077
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$W/stage-ca.crt"
rm -f "$SKC"
KUBECONFIG=$SKC kubectl config set-cluster rke2 --server=https://127.0.0.1:6443 --certificate-authority="$W/stage-ca.crt" --embed-certs >/dev/null
KUBECONFIG=$SKC kubectl config set-credentials stage-viewer --token="$TOKEN" >/dev/null
KUBECONFIG=$SKC kubectl config set-context stage --cluster=rke2 --user=stage-viewer >/dev/null
KUBECONFIG=$SKC kubectl config use-context stage >/dev/null; chmod 600 "$SKC"; unset TOKEN
SK="kubectl --kubeconfig=$SKC"
$SK auth whoami -o jsonpath='{.status.userInfo.username}' | grep -qx 'system:serviceaccount:default:stage-viewer' || die 'stage viewer: whoami'
[ "$($SK auth can-i list pods -n uyuni)" = yes ] || die 'stage viewer cannot list pods'
[ "$($SK auth can-i list secrets -A 2>/dev/null || true)" = no ] || die 'stage viewer can read secrets!'
$SK -n uyuni get ingressroutetcp >/dev/null && echo 'stage viewer OK (whoami = stage-viewer, pods yes, secrets no, ingressroutetcp readable)'
