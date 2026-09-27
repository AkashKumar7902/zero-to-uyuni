# Cases: real output, real causes

Short debugging puzzles made from real output of this lab and of Uyuni. Decide with a neighbour before you open the answer.

## Case 1 · The volume that never bound

Two PersistentVolumeClaims, two `kubectl describe pvc` event lines (captured by `lab/20-addons.sh`):

1. `waiting for first consumer to be created before binding`
2. `no persistent volumes available for this claim and no storage class is set`

Which volume is really broken?

<details><summary>Answer</summary>

**2.** Line 1 is normal: local-path binds a claim when the first pod uses it. Line 2 names no StorageClass, and the
lab has no default class, so nothing will ever bind it; `storageClassName` cannot be changed later either.
In plain words: "waiting for a program to use me" is normal; "nobody said what kind of disk to make" waits forever.
</details>

## Case 2 · The server that wouldn't boot

A Uyuni server pod crash-loops with exit code 255. This is all the log says:

```
Executing /docker-entrypoint-init.d/99-cgroupfs-mount.sh...
mount: /sys/fs/cgroup: none already mounted or mount point busy.
```

Suspects: **1** out of memory · **2** the disk is full · **3** something had already mounted `/sys/fs/cgroup` ·
**4** a wrong database password.

<details><summary>Answer</summary>

**3.** The container runtime had already mounted cgroup v2, and the start script tried again. Two programs tried to
set up the same thing; the second one crashed, and the log said so in plain words: "already mounted".
Real output from a Uyuni pull request; fixed in Uyuni 2026.08.
</details>

## Cold cases

| Case | Evidence | Answer |
|---|---|---|
| **The silent minion** | a minion's `minion.d` config looks right; `kubectl -n uyuni get svc salt` shows `ClusterIP` | a ClusterIP service is reachable only inside the cluster: Traefik's hostPorts 4505/4506 (`lab/manifests/uyuni-traefik.yaml`) are the door. Walk it: resolve → port → exposure |
| **404 by IP** | `curl -k https://<IP>/` → `404 page not found`; the FQDN gives the login page | the Ingress routes by host name: use the FQDN |
| **The restart loop** | "Startup aborted: Critically low disk space detected!" | an OS channel sync filled the disk; watch `/opt/local-path-provisioner` (`check.sh` alarms at 85 %) |
| **The chart that cannot build** | `helm dependency build` → `server-helm:2026.1.0: not found` | the example chart pins a version that no longer exists; `30-uyuni.sh` uses 2026.8.0 |
