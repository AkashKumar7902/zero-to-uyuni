# RUNNER-HQ: the stage's Uyuni HQ on a GitHub-hosted runner (v7)

`.github/workflows/hq.yml` builds HQ from zero with `lab/build.sh` (`RUNNER=1`) on an `ubuntu-24.04` runner. Because
this repo is public, that runner has 4 vCPU and 16 GB. A runner accepts no inbound connection, so every door is an
outbound tunnel, and **no web port is ever tunnelled**: the Web UI goes through an SSH tunnel.

In v7, **HQ is presenter-only**. Every attendee sandbox runs **its own HQ** (`attendee/solo.sh`, `MODE=solo` in
`server.env`). Only these join this HQ:
- the two "office servers", leap-a and leap-b;
- the **HQ table**: the speaker's sandbox plus up to 7 front-table crews, with `join.sh --hq`, **CAP 8**.

## When it runs

| Start | What happens |
|---|---|
| **Sat 3 Oct 2026, 12:37 WIB**: by itself (cron `37 5 3 10 *`, 05:37 UTC) | builds with the show's values |
| **The GitHub app**: Actions › hq › Run workflow, no field changed | the same show values: `hours 5.5 · relay bore.pub · game on · room auto · accept_min 0 · cap 8 · publish on · ssh_cf on · leaps on · drill arm` |
| `gh workflow run hq.yml -R AkashKumar7902/zero-to-uyuni -f hours=3` | a rehearsal (point the console's golden target at a `reh-` room first; the hooks then post there) |

**One HQ at a time.** Two guards stop a second HQ:
- the `concurrency: hq` group;
- the `gate` job (`lab/runner/gate.sh`).

A run that was created while another hq run was queued or running builds nothing. So a **second tap**:
- waits in the queue ("pending") while the first HQ runs;
- when the first HQ ends, starts, and the gate ends it within seconds as a duplicate. It never builds a second HQ, not
  even hours later;
- a tap made **after** the old run has ended (failed or cancelled) builds a fresh HQ, which takes about 10 min.

Never start a new run mid-show: a new HQ has a new name and a new master key.

**The schedule's real risk.** GitHub says scheduled runs "can be delayed during periods of high loads … If the load is
sufficiently high enough, some queued jobs may be dropped". A late start of 5–30 min is common; a missing run is rare
but possible. That is why:
- the cron sits at :37, away from the top of the hour, when load peaks;
- the gate builds only on 2026-10-03, and only if the run starts by **13:15 WIB**. A later cron builds nothing, so it
  can never race a phone tap;
- the plan keeps the **13:00 WIB phone check**: if hq is not running, tap Run workflow (HQ is up about 10 min later).

The cron fires every 3 Oct; the gate ignores every year but 2026. Scheduled runs use the default branch's latest
commit.

## The doors

| Door | Relay | For | Notes |
|---|---|---|---|
| SSH, first | a **Cloudflare quick tunnel** (`lab/runner/relay-cf.sh`, cloudflared 2026.9.3, sha256-pinned) | the presenter's Mac | key-only (the osas26 key). A tunnel dead for 5 min is restarted; a restart means a **new name** |
| SSH, second | **bore.pub** (`lab/runner/relay.sh`, bore 0.6.0, sha256-pinned) | the presenter's Mac | a sticky port; a watchdog restarts a dead client on the same port in about 9 s |
| Salt 4505/4506 | **bore.pub:4505/4506** exactly | the HQ table only | bore.pub resets every connection above 64 from one IP, so it cannot carry a room; 8 is well under that |

**How the Mac learns the doors.** `lab/runner/doors.sh env` is the one public record: names, ports, the SSH host
**public** key, the node address and HQ's state. `lab/runner/doors-publish.py` uploads it as a NEW artifact
`doors-N` whenever it changes (a new tunnel name, a moved port, HQ's state). `mac/door.sh` takes the newest one.

Why an artifact:
- The job summary is written only when a step ends, and the keep-alive step lasts hours, so a door's new name would
  not show there until the end.
- An artifact can be read while the run is still going, by any logged-in GitHub user, with `gh`. The Mac needs no
  new secret.
- The upload needs no write token on HQ. The job's runtime token only reaches this run's artifacts, and it is handed
  to the publisher by an action step (`actions/github-script`).
- A commit to a branch would have needed a write token on the runner that outside machines talk to. That job stays
  read-only.

Pick the newest by N, never by artifact id: ids are not in upload order.

## leap-a and leap-b

`lab/runner/leaps.sh` builds openSUSE **Leap 16.0 systemd containers** with podman on the HQ runner. The build runs in
the background while HQ builds, and each container gets its own fresh machine-id. `clients/leap16-minion.sh` runs
unchanged in each.

After HQ is up:
- **leap-a** is bootstrapped with the official script (`bootstrap-osas26.sh`), accepted and registered.
- **leap-b** stays clean. Its bootstrap is the stage cue: `door.sh leapb` on the Mac (= `leaps.sh bootstrap-b` =
  `d-bootstrap-leapb`), which prints the key fingerprint's last two pairs for the vote.
- The UI's Accept is the vote. Its fallback is `door.sh leapb accept`.
- `door.sh leapb reset` puts leap-b back to "never registered" (for rehearsals).

## The HQ table and its CAP

- `lab/runner/hq-table.sh setup 8` gives CAP 8 to three places: the Oct 3 15:55 accept timer's loop (a drop-in; its
  unit file says 60), `go-accept` (`CAP` in root's shell) and the fleet key's usage limit.
- The accept loop accepts only `^osas26-<crew>-<hex3>$` and counts them.
- The **guard** (`osas26-hqtable-guard`) **rejects** every further attendee key once CAP are trusted. The minion is
  told at once (Salt 3006 logs "The Salt Master has rejected this minion's public key" and stops).
- leap-a/leap-b and any other id are never touched.
- The refused sandbox's answer is its own HQ: `join.sh --solo`, 3 s. The kit does it by itself: `join.sh --hq`
  starts `attendee/hqwatch.sh`, which moves the sandbox to its own HQ (with a note in its terminal) when HQ says no,
  has not said yes after 10 minutes, or goes quiet (3 failed Salt knocks on 4506, 30 s apart). `MODE=solo`
  sandboxes never run it.

## Game hooks

With the defaults (`game on`, `room auto`), HQ posts to the live room:
- **inside the show window** (Oct 3, 15:00–17:30 WIB), the live room applies the posts;
- **outside it**, the posts are forwarded to the console's golden target (a `reh-` room). With no target, only HQ's
  heartbeat is recorded.

`drill arm` enables the Oct 3 drill timers, which never fire on another day. The `GOLDEN_TOKEN` secret goes to a
root-only file on HQ and is never printed.

## The Mac: `mac/door.sh` (installed as `~/osas26-kit/door/door.sh`)

```sh
bash mac/door.sh install     # cloudflared (brew, pinned), ~/.ssh/config: Host golden (Cloudflare) + golden-bore (bore.pub)
door.sh status               # the running hq run, its newest doors, HQ's state, both SSH doors probed
door.sh ssh [CMD]            # root on HQ: the Cloudflare door first, bore.pub if it does not answer
door.sh ui [--check|--open]  # the UI tunnel 127.0.0.1:18443 -> HQ:443 (background, reconnects), the 3 Meet HQ tab URLs
door.sh pass                 # the admin password to the clipboard for 45 s (never printed)
door.sh leapb [accept|reset|status]   # leap-b's live bootstrap + fingerprint tail
door.sh env                  # the day's server.env as one paste-able command (the speaker's own sandbox)
door.sh finale-files [--check]   # the golden-only finale files (Mac only) to /root/osas26, sha256-checked; mac/README.md
door.sh stop [hq]            # stop the UI tunnel; `stop hq` ends the HQ run cleanly (asks first)
```

- `~/.ssh/config` uses `ProxyCommand cloudflared access ssh`. The host name comes from the newest doors.
- The host key is pinned per run (`HostKeyAlias osas26-hq`, `StrictHostKeyChecking yes`).
- `door.sh ui --open` opens a separate Chrome window without root:
  - `--host-resolver-rules="MAP <FQDN> 127.0.0.1"`, so no `/etc/hosts` edit;
  - `--ignore-certificate-errors-spki-list`, which trusts only this HQ's certificate key, and only in that window.
- No secret is written to any file.

## Numbers

| | 2 vCPU / 7.9 GB (private repo, 27 Sep) | **4 vCPU / 16 GB (public repo, 27 Sep, run 36329160782)** |
|---|---|---|
| runner | Azure D2ads v5/v7 | Azure `Standard_D4ads_v5`, EPYC 7763, eastus2; **86 GB free on `/`** before any cleanup |
| `build.sh` | 423–459 s | **373 s** (`00` 12 · `10-rke2` 75 · `20-addons` 71 · `30-uyuni` 189 · `40` 4 · `50` 20) |
| dispatch → HQ up (`server.env`) | 9 min 22 s – 10 min 34 s | **10 min 2 s**, of which the disk cleanup took 2 min 48 s; it is now skipped when ≥ 60 GB is free (expect ≈ 7.5 min) |
| Cloudflare SSH door up | — | 3 min 9 s after the dispatch (before the build) |
| RAM, build / HQ table (8) + leap-a/b + jobs | 5.1 GB / 6.7 GB at 31 minions | **5.5 GB / 6.4 GB used, ≥ 9.5 GB available**, no swap |
| leap-a/b | — | image + both containers 62 s (during the build); leap-a registered 30 s after HQ up; leap-b's live bootstrap from the Mac 10.7 s |
| HQ table | — | the first `--hq` sandbox accepted 4 s after the accept loop opened; crew card 64 s; remote command 8/8 in 7 s |
| CAP | — | 9 joins → 8 accepted, the 9th refused 2 s after the loop ignored it |
| Mac → UI through the tunnel | 1.3–2.7 s | getVersion 0.9 s, login 1.6 s, the three tabs 1.1–1.6 s |
| a Cloudflare rename → the Mac on the new name | — | 27 s; the UI tunnel came back by itself in 6 s |

## Limits to remember

- Each run is a **new HQ**: a new node address, FQDN, master key and admin password. Sandboxes of an earlier run must
  re-run `join.sh`.
- bore.pub had a 10-s blip during the proof (all three of its doors at once, not load-related). A job sent in that
  window failed; resend it. The Cloudflare SSH door logged no restart.
- The HQ table's highstate took 64 s on a real sandbox. Seven containers that share one 4-vCPU test runner took 4.5 min
  (the test runner's contention, not HQ's).
- The logs and artifacts are **public**: nothing secret is printed, and `collect.sh` drops any file holding a secret
  value.
- Quick tunnels are "intended for testing and development only", with no SLA. bore.pub is one volunteer's service.
- GitHub's Actions terms say "develop and test". A presenter-only HQ for a few hours is defensible; the realistic
  consequence is a cancelled job, and then the room plays on (HQ-DARK).
