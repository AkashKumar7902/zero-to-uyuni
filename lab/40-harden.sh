#!/usr/bin/env bash
# 40-harden.sh (cp5) - PLAN §5.8: the CVE backport, the stage viewer, the accept timer, the aliases, golden's own key.
# Re-run after any `git pull` that changes accept-loop.sh or salt-window.sh (the units run INSTALLED copies).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/lib.sh"
lab_env; cd "$W"
t harden_start
# 1) Backport of uyuni#12486 (CVE-2026-71400): Apache rule, verbatim from upstream 01-cobblerapi.conf [L4].
#    /etc/apache2 is the etc-apache2 PVC, so it persists [K8S §2.3]. Defence in depth: 443/80 are not public anyway (D6).
kubectl -n uyuni exec -i deploy/uyuni -c uyuni -- sh -c 'cat > /etc/apache2/conf.d/zz-osas26-cobblerapi.conf && systemctl reload apache2' <<'EOF'
# Backport of uyuni-project/uyuni#12486 (CVE-2026-71400): allow cobbler api only on the localhost
<Location "/cobbler_api">
    Require ip 127.0.0.1 ::1
</Location>
EOF
code=000; for _ in $(seq 15); do code=$(curl -sk -o /dev/null -w '%{http_code}' "https://${FQDN}/cobbler_api"); [ "$code" = 403 ] && break; sleep 2; done
echo "https /cobbler_api -> $code (want 403)"; [ "$code" = 403 ] || die "/cobbler_api is not 403"
t harden_cobbler_403
# 2) the read-only kubeconfig for the projected pane (no secrets readable)
bash "$LAB/stage-viewer.sh"
t harden_stage_viewer
# 3) the persistent accept timer: unit FILES, so it survives a reboot (a transient systemd-run timer would not) - §5.11.
#    systemd (init_t) may not execute a script under /root (admin_home_t) on SELinux-enforcing Leap 16, so every unit
#    runs an installed copy (bin_t after restorecon). The Salt window script is re-installed here too.
install -m0755 "$LAB/accept-loop.sh" /usr/local/sbin/osas26-accept-loop
install -m0755 "$LAB/salt-window.sh" /usr/local/sbin/osas26-salt-window
if command -v restorecon >/dev/null; then restorecon -v /usr/local/sbin/osas26-accept-loop /usr/local/sbin/osas26-salt-window; fi
install -m0644 "$LAB/systemd/osas26-accept.service" "$LAB/systemd/osas26-accept.timer" /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now osas26-accept.timer
systemctl list-timers --all --no-pager | grep -E 'osas26-(accept|salt)'
# 4) aliases in every root shell (safe: nothing is exported), and a golden-only key for the live leap-b bootstrap
grep -q 'lab/aliases.sh' /root/.bashrc 2>/dev/null || echo ". $LAB/aliases.sh" >> /root/.bashrc
install -d -m 0700 /root/.ssh
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519 -C golden-osas26
# 5) the golden-only finale aliases (they name the volume) arrive by scp from the Mac, never via the repo before
#    Oct 3 evening:  scp ~/osas26-kit/finale-aliases.sh golden:/root/osas26/finale-aliases.sh  (aliases.sh sources it)
[ -f "$W/finale-aliases.sh" ] && echo "finale aliases: present" || echo "finale aliases: not here yet (scp them from the Mac before G3's captures)"
t harden_done
