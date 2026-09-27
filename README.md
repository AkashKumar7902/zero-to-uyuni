**Workshop attendees: start the sandbox only when the speaker says so (15:33).**

# From Zero to Uyuni

A reproducible systems-management lab: **Uyuni 2026.08** on **RKE2 + Helm**, and a fleet of browser sandboxes that
join it as Salt minions. Built for the workshop "From Zero to Uyuni" at openSUSE.Asia Summit 2026 (Yogyakarta).

> **x86_64 only.** HQ needs **≥ 4 vCPU (6 recommended), 16 GB RAM, ≥ 60 GB disk (100 GB recommended)**, a public
> IPv4 and root SSH by key. Ubuntu 24.04 or openSUSE Leap 16.0. Uyuni's own test minimum is 16 GB.

## In the room: Rule 1, the runbook, the words

**Rule 1: only inside the sandbox. A Salt master has root on its minions. Never connect your own laptop to a server you don't control.**
Use a nickname, not your full name: the screen may be photographed.
The [openSUSE Code of Conduct](https://en.opensuse.org/openSUSE:Conference_code_of_conduct) applies.

**The runbook** (a minion went dark; do the steps in this order):

```bash
venv-salt-call --local config.get master                                   # 1 config: which address does the minion REALLY use?
getent hosts "$(venv-salt-call --local config.get master | sed -n 2p | tr -d ' ')" || echo "NO DNS"   # 2 DNS
timeout 3 bash -c "</dev/tcp/$(cat /etc/osas26-fqdn)/4506" && echo OPEN || echo BLOCKED                # 3 port
grep -E 'ERROR|WARN' /var/log/venv-salt-minion.log | tail -n 5              # 4 log
systemctl restart venv-salt-minion                                          # 5 restart (Salt reads its settings only at start)
```
Frozen sandbox? Wait 1 minute, then call a helper. Don't reload on your own.

**Crew words**

| Word | Meaning |
|---|---|
| Uyuni · HQ | free, open-source software that manages many Linux machines from one place · our Uyuni server |
| minion (*mesin yang dikelola*) | a machine HQ manages (a client): your sandbox |
| master | the Salt server that gives the orders: HQ |
| FQDN (*nama host lengkap*) | the server's full name on the network |
| Helm chart | HQ's install recipe for Kubernetes (the blueprint) |
| PVC (*volume penyimpanan*) | a PersistentVolumeClaim: a request for a storage volume |
| StorageClass | which kind of disk Kubernetes makes for a PVC |
| Ingress | the door that sends web traffic to the right service |
| activation key | a class code: which team a new machine joins, which rules it gets |

**Keep playing**
- Rebuild all of HQ at home: this repo (below).
- Uyuni Community Hours: every last Thursday, online and recorded; next **Thu 29 Oct 2026, 22:00 WIB**
  ([calendar](https://calendar.opensuse.org/teams/uyuni/events/uyuni-community-hours)).
- Chat: Matrix [#uyuni-project_users:gitter.im](https://matrix.to/#/#uyuni-project_users:gitter.im).
- openSUSE Indonesia: [t.me/openSUSE_ID](https://t.me/openSUSE_ID).

## Three ways to run Uyuni

1. **As a client, in a sandbox** (the workshop): the Killercoda scenario in [`zero-to-uyuni/`](zero-to-uyuni/). Your
   sandbox renders HQ's real Helm chart, joins the fleet with [`attendee/join.sh`](attendee/join.sh), takes orders and
   survives an incident drill.
2. **A single VM with Podman** (the easiest real server): `mgradm` on openSUSE Tumbleweed or Leap Micro, see the
   [Uyuni Installation Guide](https://www.uyuni-project.org/uyuni-docs/en/uyuni/installation-and-upgrade/install-server.html).
3. **This lab: RKE2 + Helm** (what HQ runs): [`lab/`](lab/), below. It follows the
   [Kubernetes guide](https://www.uyuni-project.org/uyuni-docs/en/uyuni/specialized-guides/kubernetes-guide/server-kubernetes-deployment.html)
   with the [uyuni-charts](https://github.com/uyuni-project/uyuni-charts) wrapper and `server-helm` 2026.8.0.

## SAFETY (read before you build)

- **80 and 443 are never public.** The web UI is reached only through an SSH tunnel. (CVE-2026-71400 /
  uyuni#12486 is backported by `40-harden.sh`, as defence in depth.)
- **A host guard** ([`lab/guard.nft`](lab/guard.nft), nftables, loaded before RKE2 on every boot; RKE2 cannot start
  without it) drops 80/443, 4505/4506 and every RKE2 port (6443, 9345, 10250, 2379-2380, VXLAN, NodePorts) on the
  public interface, IPv4 and IPv6. Only SSH (22 and 2222) is open.
- **Salt (4505/4506) opens only in a window:** `osas26-salt-window open 30` (closes itself), or the two timers of
  the show day. A Salt master has root on every minion it accepts: **the accept loop takes only `osas26-<nick>-<hex>`
  ids, up to a cap, for a limited time; never `salt-key -A`.**
- **Never join your own laptop** to a lab server (Rule 1). Sandboxes and throwaway VMs only.
- `superPrivileged: true` in `values-lab.yaml` is a **lab shortcut** (SELinux/AppArmor), not for production.
- Secrets are generated on the box (`/root/osas26/secrets.env`, mode 600), never printed, never committed.
- **Destroy the VM when you are done** (and its snapshots). A lab left running costs money and is one more
  server on the internet.

## Build HQ from zero (path 3)

On a fresh **Ubuntu 24.04** (or Leap 16.0) x86_64 VM, as root:

```bash
apt-get update && apt-get install -y git          # Leap 16: zypper -n in git-core
git clone https://github.com/AkashKumar7902/zero-to-uyuni /root/zero-to-uyuni
tmux new -d -s build 'bash /root/zero-to-uyuni/lab/build.sh 2>&1 | tee /root/build.log'
tmux attach -t build                               # detach: Ctrl-b d. The build survives an SSH drop.
```

| Step | What it does | Checkpoint |
|---|---|---|
| `00-os-prep.sh` | packages, sshd key-only on 22 + 2222, the FQDN `uyuni.<a-b-c-d>.sslip.io`, **the host guard + the Salt-window timers** | cp0 |
| `10-rke2.sh` | RKE2 v1.36.4 (tarball on Ubuntu, RPM + SELinux on Leap), system images from the release tarballs, Traefik's Salt hostPorts | cp1 |
| `20-addons.sh` | Helm 4.2.4 (sha-pinned), local-path v0.0.36 + a writer/reader smoke test, cert-manager v1.21.2, trust-manager v0.24.0 | cp2, cp3 |
| `30-uyuni.sh` | Uyuni 2026.08: uyuni-charts `f3e79fb` + server-helm 2026.8.0, 26 PVCs on local-path | cp4 |
| `40-harden.sh` | the `/cobbler_api` 403 backport, a read-only "stage" kubeconfig, the accept timer, the admin aliases | cp5 |
| `50-content.sh` | groups, the crew-card state channel, activation keys `1-osas26-fleet` / `1-osas26-demo`, the bootstrap script | cp6 |
| `check.sh` | the daily health check: pods, getVersion, cluster DNS, disk, Taskomatic, keys, the guard and the window, sshd | — |

The whole build took **15 min 37 s** unattended on a 6 vCPU / 16 GB VM (about half of it downloads).
`FROM=30 bash lab/build.sh` resumes at a step. Every step appends `phase<TAB>time` to `/root/osas26/timings.tsv`;
[`docs/timings.md`](docs/timings.md) has measured numbers; [`docs/runner-hq.md`](docs/runner-hq.md) runs HQ on a GitHub runner. When something breaks: [`docs/troubleshooting.md`](docs/troubleshooting.md).

**The web UI, through a tunnel** (from your own machine; the admin password is in `/root/osas26/secrets.env`):

```bash
ssh -N -L 127.0.0.1:8443:<HQ-IP>:443 root@<HQ-IP>      # sshd on HQ connects to its own IP locally: the guard never sees it
# then open https://uyuni.<a-b-c-d>.sslip.io:8443/ with that name mapped to 127.0.0.1 (e.g. an /etc/hosts line)
```

**Operations** (`/root/zero-to-uyuni/lab/`): `accept-loop.sh` (the doors), `board.sh` (the fleet board),
`outage.sh` / `evidence.sh` (counts only), `credits.sh`, `cleanup.sh` (between rehearsals), `aliases.sh` (`d-*`),
`salt-window.sh` (installed as `osas26-salt-window`), `load-test.sh` (N containers joining HQ; also
`.github/workflows/load-test.yml`).

## Cost

The software is free. What costs money is the VM, per hour, until you destroy it.

| Item | Size | Example rate (fetched 2026-09-23) | A 3-hour session | A week |
|---|---|---|---|---|
| HQ VM | 6 vCPU / 16 GB | about US$0.11-0.15 per hour | about US$0.45 | about US$20-25 |
| two small demo VMs (optional) | 1 vCPU / 1 GB | about US$0.0075 per hour each | < US$0.05 | about US$2.5 |
| attendee sandboxes | Killercoda | free | US$0 | US$0 |

## Repo layout

```
lab/            build.sh 00-os-prep.sh 10-rke2.sh 20-addons.sh 30-uyuni.sh 40-harden.sh 50-content.sh
                check.sh cleanup.sh accept-loop.sh board.sh aliases.sh stage-viewer.sh load-test.sh
                outage.sh evidence.sh credits.sh cast-markers.py salt-window.sh guard.nft lib.sh lint-server-env.sh
lab/systemd/    osas26-accept.{service,timer} osas26-guard.service osas26-salt-{open,close}.{service,timer}
                rke2-server-10-osas26-guard.conf
lab/manifests/  uyuni-traefik.yaml local-path-storage.yaml storage-smoke.yaml.tmpl storage-smoke-reader.yaml
lab/vendor/     get-rke2-io.sh SHA256SUMS
lab/states/     welcome.sls (the crew card)
lab/loadtest/   Containerfile (one synthetic sandbox)
clients/        leap16-minion.sh reset-leap-b.sh (the Leap 16 demo clients)
attendee/       the sandbox kit: preinstall.sh join.sh catchup.sh break.sh fix.sh claim.sh hq-say.sh achieve.sh
                crew.sh game.sh probe.sh quest.sh server.env uyuni.yaml.prerendered manual.adoc.saved
zero-to-uyuni/  the Killercoda scenario (at the repo root, so it stays a scenario): index.json intro.md wait.sh
                lab1..4.md verify1..4.sh finish.md preinstall.sh assets/ (copies of attendee/*: `make killercoda`)
docs/           troubleshooting.md timings.md cases.md runner-hq.md
```

`attendee/server.env` says where HQ lives; `join.sh` fetches it from `main` at run time, so moving HQ is one push.

## Multi-arch notes

Everything is pinned for **x86_64**: the Helm tarball, the RKE2 image tarballs, and the local-path and busybox
**digest** pins (their configs say `architecture: amd64`). The Uyuni 2026.08 images themselves are multi-arch
(amd64 and arm64). An arm64 build would need the arm64 Helm and RKE2 assets and the multi-arch index digests for
local-path and busybox; it is untested, so `00-os-prep.sh` refuses anything but x86_64.

## License

MIT, see [LICENSE](LICENSE). Uyuni, Salt, RKE2, Helm and the charts are their projects' own work under their own licenses.
