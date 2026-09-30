# shellcheck shell=bash
# lab/lib.sh - sourced by the lab/NN-*.sh build steps and the ops scripts that need it.
# PLAN §5: two fixed locations, always absolute: the repo is /root/zero-to-uyuni, the work directory /root/osas26
# (timings.tsv, lab.env, secrets.env, kubeconfigs, values files). Nothing relies on the current directory.
# shellcheck disable=SC2034  # the variables below are used by the scripts that source this file
Z2U=${Z2U:-/root/zero-to-uyuni}
LAB=$Z2U/lab
W=/root/osas26
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
case ":$PATH:" in *":/var/lib/rancher/rke2/bin:"*) ;; *) PATH=$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin ;; esac
export PATH
# every step appends phase<TAB>UTC-time to ONE absolute file (rehearsal fix F5: a relative path landed inside the chart)
t(){ printf '%s\t%s\n' "$1" "$(date -u +%FT%TZ)" >> "$W/timings.tsv"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
# the host switch: Ubuntu 24.04 (the plan's lent VM, rung (d)) or openSUSE Leap 16.0 (only if a lender offers it)
lab_os(){ ( . /etc/os-release
  case "$ID:$VERSION_ID" in
    ubuntu:24.04) echo ubuntu2404 ;;
    opensuse-leap:16.0) echo leap16 ;;
    *) echo "unsupported:$ID:$VERSION_ID" ;;
  esac ) }
# load lab.env (written once by 00-os-prep.sh)
lab_env(){ [ -s "$W/lab.env" ] || die "$W/lab.env is missing: run $LAB/00-os-prep.sh first"; . "$W/lab.env"; }
# --- Canal must be the only CNI config RKE2's containerd sees (hq run 36709963322, 30 Sep: the build stopped in 30-uyuni).
# The runner image ships podman's 87-podman-bridge.conflist (10.88.0.0/16). With it in /etc/cni/net.d the node turns Ready
# BEFORE Canal writes 10-canal.conflist, so a pod created in that gap (CoreDNS, 10.88.0.5) got a second 10.88.0.0/16 bridge
# beside the leaps' podman0 (netavark), was unreachable ("no route to host"), crash-looped, and the uyuni pod's db-waiter
# never found "db" ("db:5432 - no response") until the 45-min wait ran out.
# cni_quarantine [DIR] [OFF]: move every CNI config that is not Canal's out of DIR (kept in OFF, so it can be put back).
cni_quarantine(){ local d=${1:-/etc/cni/net.d} off=${2:-/etc/cni/net.d.osas26-off} f n=0
  [ -d "$d" ] || { echo "CNI: $d does not exist yet (Canal creates it)"; return 0; }
  for f in "$d"/*.conf "$d"/*.conflist "$d"/*.json; do
    [ -f "$f" ] || continue
    case ${f##*/} in 10-canal.conflist) continue ;; esac
    install -d -m 0755 "$off"; mv -f "$f" "$off/"
    echo "CNI: ${f##*/} moved aside to $off (Canal is RKE2's only CNI)"; n=$((n + 1))
  done
  [ "$n" -gt 0 ] || echo "CNI: no other CNI config in $d"; }
# cni_strays [PREFIX] < `kubectl get pods -A -o json`: "namespace name ip" for every pod that is not hostNetwork and whose
# address is outside the cluster CIDR (RKE2's default 10.42.0.0/16): a foreign CNI config wired it (finished pods skipped).
cni_strays(){ jq -r --arg p "${1:-10.42.}" '.items[] | select(.spec.hostNetwork != true)
  | select(.status.phase != "Succeeded" and .status.phase != "Failed")
  | select((.status.podIP // "") != "") | select(.status.podIP | startswith($p) | not)
  | "\(.metadata.namespace) \(.metadata.name) \(.status.podIP)"'; }
