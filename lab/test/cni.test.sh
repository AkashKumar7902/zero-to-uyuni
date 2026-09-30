#!/usr/bin/env bash
# lab/test/cni.test.sh - offline regression test for lib.sh's cni_quarantine and cni_strays (make check runs it).
# The case is hq run 36709963322 (30 Sep): podman's 87-podman-bridge.conflist sat beside Canal's config, CoreDNS got
# 10.88.0.5, crash-looped, and 30-uyuni waited 45 min for a database it could not name. No root, no cluster, no network.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$2"; fi; }

# 1. cni_quarantine: podman's bridge config leaves, Canal's stays, nothing else is touched
d=$T/net.d; off=$T/off; mkdir -p "$d"
printf '{"cniVersion":"0.4.0","name":"podman","plugins":[{"type":"bridge","bridge":"cni-podman0","ipam":{"ranges":[[{"subnet":"10.88.0.0/16"}]]}}]}\n' > "$d/87-podman-bridge.conflist"
echo '{"name":"k8s-pod-network"}' > "$d/10-canal.conflist"; echo 'kubeconfig' > "$d/calico-kubeconfig"; echo '{}' > "$d/99-other.conf"
out=$(cni_quarantine "$d" "$off")
ok "quarantine keeps Canal and its kubeconfig" "$(cd "$d" && ls | tr '\n' ' ')" "10-canal.conflist calico-kubeconfig "
ok "quarantine keeps what it moved" "$(cd "$off" && ls | tr '\n' ' ')" "87-podman-bridge.conflist 99-other.conf "
ok "quarantine says what it moved" "$(grep -c 'moved aside' <<<"$out")" "2"
ok "a second run moves nothing" "$(cni_quarantine "$d" "$off")" "CNI: no other CNI config in $d"
ok "a missing directory is fine (RKE2 creates it)" "$(cni_quarantine "$T/none" "$off"; echo "rc=$?")" "CNI: $T/none does not exist yet (Canal creates it)
rc=0"

# 2. cni_strays: the 30 Sep cluster as `kubectl get pods -A -o json` showed it
cat > "$T/pods.json" <<'JSON'
{"items":[
 {"metadata":{"namespace":"kube-system","name":"rke2-coredns-rke2-coredns-6b85489767-sfrtt"},"spec":{},"status":{"phase":"Running","podIP":"10.88.0.5"}},
 {"metadata":{"namespace":"kube-system","name":"rke2-canal-4gznl"},"spec":{"hostNetwork":true},"status":{"phase":"Running","podIP":"10.1.0.65"}},
 {"metadata":{"namespace":"kube-system","name":"helm-install-rke2-coredns-d4xrn"},"spec":{"hostNetwork":true},"status":{"phase":"Succeeded","podIP":"10.1.0.65"}},
 {"metadata":{"namespace":"kube-system","name":"helm-install-rke2-traefik-crd-ns64z"},"spec":{},"status":{"phase":"Succeeded","podIP":"10.88.0.3"}},
 {"metadata":{"namespace":"kube-system","name":"rke2-traefik-hmtdf"},"spec":{},"status":{"phase":"Running","podIP":"10.42.0.11"}},
 {"metadata":{"namespace":"uyuni","name":"db-6987fbbdcf-v6h44"},"spec":{},"status":{"phase":"Running","podIP":"10.42.0.27"}},
 {"metadata":{"namespace":"uyuni","name":"uyuni-7f94c7d94b-fkmrg"},"spec":{},"status":{"phase":"Pending","podIP":"10.42.0.49"}},
 {"metadata":{"namespace":"uyuni","name":"not-scheduled-yet"},"spec":{},"status":{"phase":"Pending"}}
]}
JSON
ok "strays: only the running CoreDNS on 10.88" "$(cni_strays 10.42. < "$T/pods.json")" "kube-system rke2-coredns-rke2-coredns-6b85489767-sfrtt 10.88.0.5"
ok "strays: a healthy cluster has none" "$(grep -v coredns-6b85489767-sfrtt "$T/pods.json" | cni_strays 10.42.)" ""
ok "strays: empty input (kubectl failed) is none" "$(printf '' | cni_strays 10.42.; echo "rc=$?")" "rc=0"

echo "cni.test.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
