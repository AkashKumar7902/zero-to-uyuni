---
name: The lab broke
about: A lab/*.sh step failed while you rebuilt HQ
labels: lab
---

**Which step** (`lab/NN-*.sh`) and its last 30 lines of output (no passwords: `secrets.env` is never printed by the scripts):

**Host**: `cat /etc/os-release | head -2`, `uname -m`, `nproc`, `free -g`, `df -h /`

**`bash /root/zero-to-uyuni/lab/check.sh`** output:

**`/root/osas26/timings.tsv`** (the phase marks):
