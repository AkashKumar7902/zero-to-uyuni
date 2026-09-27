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
