# RUNNER-HQ: HQ on a GitHub-hosted runner

`.github/workflows/hq.yml` builds HQ from zero with `lab/build.sh` (`RUNNER=1`) on an `ubuntu-24.04` runner and opens
its doors through public relays that need no account. A runner accepts no inbound connection, so every door is an
outbound tunnel; **no web port is ever tunnelled** (the Web UI is an SSH tunnel).

```sh
gh workflow run hq.yml -R AkashKumar7902/zero-to-uyuni -f hours=5.5 -f relay=cloudflare-quick -f game=off
gh run download <run id> -R AkashKumar7902/zero-to-uyuni -n doors        # the SSH doors, readable within ~2 min
gh run download <run id> -R AkashKumar7902/zero-to-uyuni -n server-env   # when HQ is up (~10 min)
ssh -p <SSH_PORT> root@bore.pub touch /root/osas26/runner/STOP           # end early; the logs still upload
```

## The relays

| `relay` | Salt doors | Sandbox side | Measured (27 Sep 2026) |
|---|---|---|---|
| `bore.pub` | `bore.pub:4505/4506` exactly (bore v0.6.0, sha256-pinned; `lab/runner/relay.sh`) | the kit as it is | fine for a few minions; **31 collapsed**: bore.pub resets every connection of an IP holding more than 64 connections to its port 7835, and the bore client opens one per tunnelled connection (2 per minion, 3-4 during a job) |
| `bore.pub-any` | any free bore.pub ports | needs `master_port` + `publish_port` in the minion config (kit change D-K2) | not run |
| `cloudflare-quick` | two trycloudflare quick tunnels (`lab/runner/relay-cf.sh`, cloudflared 2026.9.3, sha256-pinned) | `lab/loadtest/cf-doors.sh`: two local forwarders on 127.0.0.1:4505/4506 (kit change D-K3); `server.env` says `SERVER_IP=127.0.0.1` | **31 minions**: registration, crew-card highstate, remote command, an outage storm, 15+ min idle, all green |

The SSH door is always on bore.pub (key-only); with `cloudflare-quick` a second one goes through Cloudflare:
`ssh -o ProxyCommand='cloudflared access ssh --hostname %h' root@<CF_SSH_HOST>`.

Why exactly 4505/4506 on bore.pub: `join.sh` sets only `master:`, and a Salt 3006 minion takes the publish port the
master advertises at auth unless its own config sets `publish_port` (`salt/channel/client.py`).

## `RUNNER=1`

- No nft host guard and no Salt-window timers: the only way in is the tunnels, which arrive on the node itself.
- The 4 vCPU / 16 GB floor is a warning (a private repo's runner has 2 vCPU / 8 GB; a public repo's 4 / 16).
- The FQDN is `uyuni.<runner's private IP>.sslip.io`; sandboxes map it to `SERVER_IP` in `/etc/hosts` (`join.sh`).
- Docker is stopped before RKE2; ~36 GB of preinstalled toolchains are removed (`lab/runner/prep.sh`).

## Numbers

| | 2 vCPU / 7.9 GB runner |
|---|---|
| `build.sh` | 423–459 s (`10-rke2` 112–151, `20-addons` 74–85, `30-uyuni` 193–194) |
| dispatch → `server-env` | ≈ 10 min |
| RAM with 31–33 minions | 6.7 GB used, ≥ 1.2 GB available, no swap |
| a job's limit | 6 h (`timeout-minutes: 358`) |

## Limits to remember

- Each run is a **new HQ** (new private IP, FQDN, master key, admin password): sandboxes of an earlier run must
  re-run `join.sh` and forget the old master key.
- `server.env` reaches sandboxes through `raw.githubusercontent.com/.../main/attendee/server.env` only while the repo
  is public (`publish=true` commits it there).
- Quick tunnels are "intended for testing and development only", hold 200 in-flight requests each, and get a new name
  when cloudflared restarts (`cf-doors.sh` follows `server.env`).
