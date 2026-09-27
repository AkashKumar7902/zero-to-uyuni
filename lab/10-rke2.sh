#!/usr/bin/env bash
# 10-rke2.sh (cp1) - PLAN §5.5: RKE2 v1.36.4 + the Salt door (Traefik hostPorts 4505/4506), behind the host guard.
#   ubuntu2404  rung (d): the TARBALL method, no `selinux:`, AppArmor (FREE-GOLDEN §8.2, table row 5.5)
#   leap16      the RPM method (rke2-selinux, `selinux: true`), restorecon, the container_runtime_t check
# System images come from the release tarballs (no docker.io pulls: 100 per IPv4 per 6 h [R20]); the two Uyuni images
# are pre-pulled while RKE2 starts. Safe to re-run: an installed v1.36.4 is not reinstalled.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
lab_env; cd "$W"
nft list table inet osas26_guard >/dev/null 2>&1 || die "the host guard is not loaded: run 00-os-prep.sh first (RKE2 never starts without it)"
t rke2_start
V=v1.36.4+rke2r1; U="https://github.com/rancher/rke2/releases/download/${V/+/%2B}"
IMG=/var/lib/rancher/rke2/agent/images
mkdir -p /etc/rancher/rke2 /var/lib/rancher/rke2/server/manifests "$IMG"
{ echo 'write-kubeconfig-mode: "0600"'
  [ "$OS" = leap16 ] && echo 'selinux: true'
  echo 'ingress-controller: traefik'
  echo "tls-san: [\"${FQDN}\", \"${PUB_IP}\"]"; } > /etc/rancher/rke2/config.yaml
echo "=== DOOR: Salt is ClusterIP - Traefik opens 4505/4506 (HelmChartConfig) ==="   # trap-bingo banner 1 (§5.14.8); <= 78 columns
install -m0644 "$LAB/manifests/uyuni-traefik.yaml" /var/lib/rancher/rke2/server/manifests/uyuni-traefik.yaml
# pre-pull the Uyuni images while RKE2 starts (an image list: *.txt in the images directory) [RKE2 §4.2]
printf '%s\n' registry.opensuse.org/uyuni/server:2026.08 registry.opensuse.org/uyuni/server-postgresql:2026.08 > "$IMG/uyuni-2026.08.txt"
# the system images as release tarballs, checked against the release's sha256 list. The list itself is kept OUT of the
# images directory: RKE2 would read any *.txt there as an image list.
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
curl -fsSL --retry 3 -o "$S/sha256sum-amd64.txt" "$U/sha256sum-amd64.txt"
for f in rke2-images-core.linux-amd64.tar.zst rke2-images-canal.linux-amd64.tar.zst; do
  if ! (cd "$IMG" && grep -E " $f\$" "$S/sha256sum-amd64.txt" | sha256sum -c --quiet - 2>/dev/null); then
    curl -fsSL --retry 3 -o "$IMG/$f" "$U/$f"; fi
done
(cd "$IMG" && grep -E ' rke2-images-(core|canal)\.linux-amd64\.tar\.zst$' "$S/sha256sum-amd64.txt" | sha256sum -c -)
(cd "$LAB/vendor" && sha256sum -c SHA256SUMS)                  # the vendored installer [CF §6.1; L16]
if command -v rke2 >/dev/null && rke2 --version 2>/dev/null | grep -q "${V}"; then
  echo "RKE2 $V already installed"
elif [ "$OS" = leap16 ]; then
  # repo rpm.rancher.io/rke2/stable/1.36/microos, pulls rke2-selinux + iptables [L16; RKE2 §2.1]; if it fails, the §5.5 ladder
  INSTALL_RKE2_METHOD=rpm INSTALL_RKE2_VERSION=$V sh "$LAB/vendor/get-rke2-io.sh"
  restorecon -R /var/lib/rancher/rke2 || true                  # files staged before the install [RKE2 §2.2 b5]
else
  INSTALL_RKE2_METHOD=tar INSTALL_RKE2_VERSION=$V sh "$LAB/vendor/get-rke2-io.sh"   # installs to /usr/local [R4]
fi
systemctl daemon-reload
systemctl show rke2-server -p Requires --value | grep -qw osas26-guard.service || die "rke2-server does not Require osas26-guard.service"
t rke2_installed
systemctl enable --now rke2-server                               # blocks until the server is up (image import + pre-pull)
for b in kubectl crictl ctr; do ln -sf "/var/lib/rancher/rke2/bin/$b" "/usr/local/bin/$b"; done
for _ in $(seq 120); do kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 5; done
kubectl wait node --all --for=condition=Ready --timeout=10m
rke2 --version | head -1 > rke2-version.txt; cat rke2-version.txt
if [ "$OS" = leap16 ]; then
  # `ps -eZ` prints only the comm name "rke2", so grepping it for "rke2 server" never matches [R3]
  ps -eo label,args | grep '[r]ke2 server' > rke2-selinux.log || true
  grep -q container_runtime_t rke2-selinux.log || die 'rke2 server is NOT in container_runtime_t - walk the §5.5 ladder'
else
  echo "MAC: AppArmor ($(aa-enabled 2>/dev/null || echo unknown)); no SELinux checks on this host"
fi
t rke2_ready
# the Salt door: the rke2-traefik chart must pick up the HelmChartConfig (hostPorts are DNAT rules, not sockets)
for _ in $(seq 120); do
  hp=$(kubectl -n kube-system get ds rke2-traefik -o jsonpath='{range .spec.template.spec.containers[0].ports[*]}{.hostPort}{" "}{end}' 2>/dev/null || true)
  case " $hp " in *" 4506 "*) break ;; esac; sleep 5; done
case " $hp " in *" 4505 "*" 4506 "*|*" 4506 "*" 4505 "*) echo "rke2-traefik hostPorts: $hp" ;;
  *) kubectl -n kube-system logs job/helm-install-rke2-traefik --tail=40 || true
     die "Traefik has no Salt hostPorts (if the job rejects the values: remove containerPort, §5.5)" ;; esac
kubectl -n kube-system rollout status ds/rke2-traefik --timeout=10m
kubectl -n kube-system get helmchart,helmchartconfig | grep -i traefik
iptables -t nat -S | grep -E -- '--dport (4505|4506)' || die "no Salt DNAT rules"
np=$(kubectl get svc -A --no-headers | grep -c NodePort || true)
[ "$np" = 0 ] || { kubectl get svc -A | grep NodePort; die "$np NodePort service(s): G-FW requires 0"; }
echo "services with a NodePort: 0"
t rke2_door
