# Troubleshooting HQ

Start with `bash /root/zero-to-uyuni/lab/check.sh`: every FAIL line names its fix. Then find the symptom below.

## The build

| Symptom | Cause | Fix |
|---|---|---|
| `00-os-prep.sh`: `FQDN resolves to ..., not <ip>` | the resolver cannot reach sslip.io, or drops answers that point to private addresses | fix DNS first. The Uyuni pod must resolve its **own** FQDN through cluster DNS, or setup crashes at "Setting up Cobbler: Neither IPv4 nor IPv6 addresses can be resolved" |
| `00-os-prep.sh`: `PORT-BUSY` | something already listens on 80/443/4505/4506/6443/9345 (a stray nginx or salt-master) | stop it; nothing else may own these ports |
| `10-rke2.sh`: `the host guard is not loaded` | 00 did not run, or `osas26-guard.service` failed | `systemctl status osas26-guard`; `nft -c -f /etc/osas26/guard.nft` |
| `10-rke2.sh`: `Traefik has no Salt hostPorts` | the rke2-traefik chart rejected the HelmChartConfig | `kubectl -n kube-system logs job/helm-install-rke2-traefik`; if it names `containerPort`, remove that key from `lab/manifests/uyuni-traefik.yaml` |
| `10-rke2.sh` on Leap 16: `rke2 server is NOT in container_runtime_t` | the RPM/SELinux path failed | PLAN §5.5's ladder: (b) the tarball method, (c) `setenforce 0` (say so honestly), (d) Ubuntu 24.04 |
| `20-addons.sh`: a smoke pod `Error` on SELinux | the local-path helper pod's MCS labels | add `securityContext: {seLinuxOptions: {level: "s0-s0:c0.c1023"}}` to `helperPod.yaml` in the `local-path-config` ConfigMap, restart the provisioner, re-run |
| `30-uyuni.sh` waits a long time | the first boot pulls ≈ 850 MB of images and populates the database | normal up to ≈ 10 min; watch `kubectl -n uyuni get pods -w` and `kubectl -n uyuni logs deploy/uyuni -c uyuni -f` |
| the uyuni pod hangs in `db-waiter` ("db:5432 - no response") | CoreDNS forwards to a resolver the host no longer uses (the host changed networks), and the database reverse-resolves every client | `kubectl -n kube-system rollout restart deploy/rke2-coredns-rke2-coredns`, then restart the uyuni pod. `check.sh` tests this ("cluster DNS") |
| the uyuni pod crash-loops | see its log | `kubectl -n uyuni logs deploy/uyuni -c uyuni --previous`; on Leap 16 also `ausearch -m AVC -ts recent` (`superPrivileged` covers only the server container, not `deploy/db` or the local-path helper) |
| `kubectl rollout status` gives up after 10 min on a first install | the Deployment's 600-s progress deadline, whatever `--timeout` says | the scripts wait with `kubectl wait --for=condition=Available` instead |
| `helm dependency build`: `server-helm:2026.1.0: not found` | the example chart's dead pin | `30-uyuni.sh` rewrites it to 2026.8.0 (trap 2 on the build's screen) |
| a 502 from the UI right after the pod turns Ready | systemd inside the container is still starting services | wait; getVersion answers ≈ 15 s later |
| `50-content.sh` hangs | a spacecmd prompt | every call uses the global `-y`, and `activationkey_addconfigchannels -t` (without `-t` it asks "top or bottom?") |

## The host guard and the Salt window

- `osas26-salt-window status` shows the guard, the window, `lab_ok` and the timers.
- Open for a test: `osas26-salt-window open 30` (it closes itself). Close now: `osas26-salt-window close`.
- A separate demo VM that must reach HQ: `osas26-salt-window lab-add <ip>` (kept in `/etc/osas26/lab-ok.list`).
- Never enable Ubuntu's `nftables.service` or run `nft flush ruleset`: they wipe RKE2's own tables too. If it
  happened: `systemctl restart osas26-guard rke2-server`.
- After a reboot the guard comes back first; `reconcile` reopens the window only inside the show window.
- Prove it from **outside**: `for p in 80 443 6443 9345 10250 2379 4505 4506; do nc -z -w 5 <ip> $p && echo "$p OPEN"; done`
  prints nothing when the window is closed; 22 and 2222 answer.

## The fleet

| Symptom | Where to look |
|---|---|
| a sandbox's key never shows as pending | on the sandbox: `timeout 3 bash -c "</dev/tcp/<fqdn>/4506"` (is the window open?), `tail /var/log/venv-salt-minion.log` |
| pending but never accepted | the accept loop: `journalctl -u osas26-accept -u osas26-accept-manual`; the id must match `osas26-<2-12 a-z0-9>-<3 hex>`; the cap |
| accepted but not registered | give it 10-60 s (Uyuni's registration queue); `kubectl -n uyuni exec deploy/uyuni -c uyuni -- tail -50 /var/log/rhn/rhn_web_ui.log` |
| two sandboxes collapse into one system | the same machine-id: `join.sh` writes a fresh one; clones must never share it |
| Level 4 CHECK says "restart the minion" | the config was fixed but Salt reads it only at start: `systemctl restart venv-salt-minion` |
| after joining, `apt install` finds nothing in the sandbox | expected: registration applies Uyuni's `channels` state, which disables the machine's own apt sources (`Enabled: no`) and installs HQ's CA under `/usr/local/share/ca-certificates/susemanager/`; a client gets its software from HQ's channels. The lab's sandboxes have no channels on purpose |
| `cleanup.sh` refuses | record the counts first (`d-savecounts`), or `FORCE=1` in a rehearsal |
| the system list still shows deleted systems | deletion is asynchronous and spacecmd caches the list: `cleanup.sh` waits and runs `clear_caches` |
