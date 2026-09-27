# mac/: the presenter's door to RUNNER-HQ

`door.sh` connects the presenter's Mac to the HQ that `.github/workflows/hq.yml` builds on a GitHub runner. Every run
builds a new HQ behind new doors (a Cloudflare quick tunnel and a bore.pub port). So nothing is typed by hand: the
script reads the run's newest public `doors-N` artifact with `gh`, and `ssh` reads that through `ProxyCommand`.

```sh
bash mac/door.sh install        # once: copies itself to ~/osas26-kit/door/, cloudflared (brew, pinned), ~/.ssh/config
~/osas26-kit/door/door.sh status
```

The full command list and the numbers are in [`docs/runner-hq.md`](../docs/runner-hq.md).

Once HQ is up (`door.sh status` says `up`), copy the golden-only finale files to it. They stay on the Mac and never
go into this repo before Oct 3 evening:

```sh
~/osas26-kit/door/door.sh finale-files           # copy what is missing or changed, then check each file by sha256
~/osas26-kit/door/door.sh finale-files --check   # compare only
```

| On the Mac | On HQ | Read by |
|---|---|---|
| `kit/golden/aliases-final.sh` in the workshop folder (or `~/osas26-kit/finale-aliases.sh`) | `/root/osas26/finale-aliases.sh` | `lab/aliases.sh` (a new shell or tmux window) |
| `~/osas26-kit/credits-extra.txt` | `/root/osas26/credits-extra.txt` | `lab/credits.sh` (`d-credits`) |

It is safe to run again: a file that is already the same is left alone. It prints names, sizes and hashes only, never
the content.

It needs `gh` (logged in with any GitHub account), `jq`, `python3`, `openssl`, `curl`, `nc`, and the osas26 SSH key
at `~/.ssh/osas26_ed25519`. No secret is ever written to a file: the admin password is fetched over SSH only when
you ask for it (`door.sh pass` puts it on the clipboard for 45 s).
