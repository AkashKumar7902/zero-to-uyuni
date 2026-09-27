# Timings

Every `lab/*.sh` step appends `phase<TAB>UTC-time` to `/root/osas26/timings.tsv`, and `build.sh` writes the seconds
per step to `/root/osas26/build-phases.tsv`. These are the lab's recorded numbers.

## HQ from zero on Ubuntu 24.04 (27 Sep 2026)

A fresh Ubuntu 24.04.5 cloud image as a KVM guest (6 vCPU, 16 GB, 60 GB disk) on a home connection; the repo as a
plain clone; `bash lab/build.sh` in tmux, unattended.

| Step | Seconds | Inside it |
|---|---|---|
| `00-os-prep` | 23 | apt packages, sshd on 22 + 2222, the host guard + the Salt-window timers |
| `10-rke2` | 554 | download + install 458 (the two image tarballs, 801 MB, and the RKE2 tarball), RKE2 start → node Ready 51, Traefik's Salt door 45 |
| `20-addons` | 129 | Helm + local-path + the writer/reader smoke test 48, cert-manager + trust-manager 61, the Case 1 events 20 |
| `30-uyuni` | 199 | helm install 6, db Available 5, uyuni Available 173, getVersion 200 +15 (the Uyuni images were pre-pulled while RKE2 started) |
| `40-harden` | 4 | `/cobbler_api` 403 after 3 |
| `50-content` | 26 | groups, the crew-card channel, the keys, the bootstrap script |
| **total** | **937 (15 min 37 s)** | then `check.sh`: all OK |

About half of the total is downloading (≈ 1.7 GB: RKE2's images, Uyuni's two images, charts). An earlier run of the same
steps on the same link took 4 min 20 s instead of 7 min 38 s for the downloads, so plan **≈ 13-16 min** on a home link
and less in a datacenter. Creating the VM itself took 14 s to SSH.

## The fleet on that HQ

| Moment | Measured |
|---|---|
| `join.sh` (a systemd sandbox) | 1 s; accepted 5 s after it ended; registered 11 s after the accept |
| two Ubuntu 24.04 containers (`load-test.sh 2`, the non-systemd branch; image build 116 s) | accepted 4 s after they started; registered 10-12 s after the accept |
| Level 3: the order edit + Apply Highstate (API) → the new crew card in `/etc/motd` | 5 s |
| a remote command (`hq-say.sh`) → completed, banner in the terminal | 1 s |
| Apply Highstate on 3 minions → 3 crew cards | ≤ 15 s |
| `d-highstate` · `d-ping` | 5-6 s · < 1 s |
| `outage.sh roster` · a check with 1 of 1 dark · a check with all back · `evidence.sh` | 1 s · 11 s · 2 s · 11 s |
| `credits.sh` (FAST=1) · `cleanup.sh` (3 systems) | 5 s · 28 s |
| `osas26-salt-window open 1` → closed again | 61 s |
| a dark minion answers again after the window reopens | 1 s |

## Reboot (G-REBOOT)

| Moment | Measured |
|---|---|
| the host guard loaded | 3.7 s after boot (RKE2 starts at 6.5 s) |
| SSH answers | 98 s after `systemctl reboot` (most of it is the shutdown of the pods) |
| db Ready · uyuni Ready | 36 s · 4 min 2 s after boot (5 min 36 s after the reboot command) |
| 80, 443, 6443, 10250 from the network | never reachable; 4505/4506 only inside the test windows |

## Dress rehearsal on an existing RKE2 (26 Sep, warm image cache; not from zero)

| Phase | Measured |
|---|---|
| `30-uyuni.sh`, clean install on warm images | 197 s (helm 3 s, db Available 8 s, uyuni Available 171 s, getVersion +15 s) |
| first image pulls | server 678 MB in 71.5 s, server-postgresql 168 MB in 27.5 s |
| doors: accept loop start → first accept | 14 s (1 minion); 15.5-16.6 s (2) |
| accept → registered | 7 s (1 minion); 30-40 s (2 at once) |
| pod restart → getVersion 200 | 171 s (rollout restart); 203 s from scale 0 → 1 |

Registration at room scale (30-60 at once) is measured by the load test (`lab/load-test.sh`, `.github/workflows/load-test.yml`).
