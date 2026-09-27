# mac/: the presenter's door to RUNNER-HQ

`door.sh` connects the presenter's Mac to the HQ that `.github/workflows/hq.yml` builds on a GitHub runner. Every run
builds a new HQ behind new doors (a Cloudflare quick tunnel and a bore.pub port). So nothing is typed by hand: the
script reads the run's newest public `doors-N` artifact with `gh`, and `ssh` reads that through `ProxyCommand`.

```sh
bash mac/door.sh install        # once: copies itself to ~/osas26-kit/door/, cloudflared (brew, pinned), ~/.ssh/config
~/osas26-kit/door/door.sh status
```

The full command list and the numbers are in [`docs/runner-hq.md`](../docs/runner-hq.md).

It needs `gh` (logged in with any GitHub account), `jq`, `python3`, `openssl`, `curl`, `nc`, and the osas26 SSH key
at `~/.ssh/osas26_ed25519`. No secret is ever written to a file: the admin password is fetched over SSH only when
you ask for it (`door.sh pass` puts it on the clipboard for 45 s).
