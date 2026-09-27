# Timings

Every `lab/*.sh` step appends `phase<TAB>UTC-time` to `/root/osas26/timings.tsv`, and `build.sh` writes the seconds
per step to `/root/osas26/build-phases.tsv`. These are the lab's recorded numbers.

## Build from zero on Ubuntu 24.04 (test VM: 6 vCPU, 16 GB, 60 GB)

(filled from the first unattended from-zero run)

## Dress rehearsal on an existing RKE2 (warm image cache; not from zero)

| Phase | Measured |
|---|---|
| `30-uyuni.sh`, clean install on warm images | 197 s (helm 3 s, db Available 8 s, uyuni Available 171 s, getVersion +15 s) |
| first image pulls | server 678 MB in 71.5 s, server-postgresql 168 MB in 27.5 s |
| `40-harden.sh` | 5 s (`/cobbler_api` 403 at +3 s) |
| `50-content.sh` | 22 s |
| a sandbox's preinstall + `join.sh` (Ubuntu 24.04, non-systemd) | 46 s |
| doors: accept loop start → first accept | 14 s (1 minion); 15.5-16.6 s (2) |
| accept → registered | 7 s (1 minion); 30-40 s (2 at once) |
| highstate → crew card in `/etc/motd` | 3 s (1 minion, CLI); 7-8 s (2, UI) |
| a remote command returns | 15 s for 2 of 2 |
| `outage.sh` check with 1 dark node | 11 s · `evidence.sh` 11.6 s |
| pod restart → getVersion 200 | 171 s (rollout restart); 203 s from scale 0 → 1 |
