#!/usr/bin/env bash
# 30-uyuni.sh (cp4) - PLAN §5.7: Uyuni 2026.08 through the uyuni-charts wrapper (f3e79fb) and server-helm 2026.8.0.
# The wrapper's default users are admin, susemanager, postgres and pythia, so only passwords are set [L24].
# Rehearsal fixes: F3 (wait on condition=Available: `rollout status` gives up at the 600-s progress deadline whatever
# --timeout says) and F5 (timings to /root/osas26/timings.tsv). Secrets are generated here, never printed.
set -euo pipefail; set +x
. "$(dirname "$(readlink -f "$0")")/lib.sh"
lab_env; cd "$W"
t uyuni_start
umask 077
[ -s secrets.env ] || { g(){ openssl rand -hex 16; }; printf 'ADMIN_PASS=%s\nDB_INT=%s\nDB_ADM=%s\nDB_REP=%s\n' "$(g)" "$(g)" "$(g)" "$(g)" > secrets.env; }
. ./secrets.env                                                   # NEVER cat on screen; copy ADMIN_PASS to the password manager off-projector
[ -d uyuni-charts ] || git clone -q https://github.com/uyuni-project/uyuni-charts
git -C uyuni-charts fetch -q origin 2>/dev/null || true
git -C uyuni-charts checkout -q -f f3e79fbb537e14bbf0b4a835bb1c2b3d9ce123b1                    # [L5]
cd uyuni-charts/server-selfsigned
echo "=== PIN: example chart needs server-helm 2026.1.0 (gone) - use 2026.8.0 ==="   # trap-bingo banner 2; <= 78 columns
sed -i -e 's#oci://registry.opensuse.org/systemsmanagement/uyuni/master/charts/uyuni#oci://registry.opensuse.org/uyuni#' \
       -e 's/version: 2026.1.0/version: 2026.8.0/' Chart.yaml                                 # the dead pin [L5; K8S §8 #12]
# HEDGE if a new release removed 2026.8.0 from /uyuni/ (retention is not guaranteed: 2026.06 already vanished [R9]):
#   chart:  oci://registry.opensuse.org/systemsmanagement/uyuni/snapshots/2026.08/charts/uyuni [L1]
#   images: add  repository: registry.opensuse.org/systemsmanagement/uyuni/snapshots/2026.08/containerfile/uyuni
#           under server-helm: in values-lab.yaml (the chart builds <repository>/<name>:<tag> [R10])
helm dependency build                                              # expect charts/server-helm-2026.8.0.tgz
ls charts/
cat > "$W/secrets-values.yaml" <<EOF
credentials:
  admin: {password: "${ADMIN_PASS}"}
  db:
    internal: {password: "${DB_INT}"}
    admin:    {password: "${DB_ADM}"}
    reportdb: {password: "${DB_REP}"}
EOF
cat > "$W/values-lab.yaml" <<EOF
global: {fqdn: "${FQDN}"}
certManagerNamespace: cert-manager
ssl: {country: "ID", province: "DI Yogyakarta", locality: "Yogyakarta", org: "oSAS26 Uyuni lab", orgUnit: "workshop", email: "admin@example.invalid"}
server-helm:
  tag: "2026.08"
  pullPolicy: IfNotPresent            # never copy sumaform's "Always" [K8S §9]
  volumes: {storageClass: local-path} # named explicitly: a teaching point [ASSETS §d.1]
  server: {superPrivileged: true}     # LAB ONLY: SELinux spc_t on Leap 16 / AppArmor unconfined on Ubuntu; proper fix = selinuxType uyuni_container_t [K8S §8 #2]
EOF
echo "=== LAB ONLY: superPrivileged: true - SELinux shortcut, not for production ==="   # trap-bingo banner 3; <= 78 columns
helm upgrade --install uyuni . -n uyuni --create-namespace \
  -f "$W/values-lab.yaml" -f "$W/secrets-values.yaml" --timeout 30m
t uyuni_helm_done
kubectl -n uyuni wait deploy/db    --for=condition=Available --timeout=30m     # F3
t uyuni_db_ready
kubectl -n uyuni wait deploy/uyuni --for=condition=Available --timeout=45m     # 502s are normal while systemd starts [K8S §7]
t uyuni_pod_ready
end=$(( $(date +%s) + 3600 ))
until curl -skf -o /dev/null "https://${FQDN}/rhn/manager/api/api/getVersion"; do
  [ "$(date +%s)" -lt "$end" ] || die "getVersion not 200 after 60 min (kubectl -n uyuni logs deploy/uyuni -c uyuni)"; sleep 15; done
echo "getVersion: $(curl -sk "https://${FQDN}/rhn/manager/api/api/getVersion")"
t uyuni_ready
# counts only: the build cast must not show volume NAMES (spoiler, §4A.7)
kubectl -n uyuni get pvc -o custom-columns=CLASS:.spec.storageClassName,STATUS:.status.phase --no-headers | sort | uniq -c
