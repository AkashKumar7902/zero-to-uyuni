# Level 4 · Incident drill

Wait for **Go** on the projector. Then: `/root/osas26/break.sh`{{exec}} (the pager goes off).
break.sh cuts your minion off from its HQ: your own master (at the HQ table: Uyuni).

Find out what broke, in this order (the runbook):

1 · config: what does your minion REALLY use as HQ's address?
`venv-salt-call --local config.get master`{{exec}}
(Which files say it? `grep -H '^master' /etc/venv-salt-minion/minion.d/*.conf`{{exec}})

2 · DNS: can your machine turn that name into a number?
`getent hosts "$(venv-salt-call --local config.get master | sed -n 2p | tr -d ' ')" || echo "NO DNS"`{{exec}}

3 · port: can it reach HQ's door 4506?
`timeout 3 bash -c "</dev/tcp/$(cat /etc/osas26-fqdn)/4506" && echo OPEN || echo BLOCKED`{{exec}}

4 · log: what did the minion write in its diary?
`grep -E 'ERROR|WARN' /var/log/venv-salt-minion.log | tail -n 5`{{exec}}

Fix it by hand:
- wrong name in the config: `sed -i "s/^master: .*/master: $(cat /etc/osas26-fqdn)/" /etc/venv-salt-minion/minion.d/*.conf`{{exec}}
- port BLOCKED: find the rule with `iptables -S OUTPUT`{{exec}}, then remove it: `iptables -D OUTPUT -p tcp --dport 4506 -j REJECT`{{exec}}

5 · restart (after any config change): `systemctl restart venv-salt-minion`{{exec}} (Salt reads its settings only when it starts.)

When the speaker says **"fix.sh allowed"**, `/root/osas26/fix.sh`{{exec}} is fine too: real SREs use runbooks.

**Is it back?** After step 5, ask your master (the minion needs about 10 seconds): `salt "$(cat /etc/osas26-id)" test.ping`{{exec}}
While door 4506 is blocked, your own `salt` commands wait too: they use the same door.

Press **CHECK**. When the projector says **Promotions**, they come from you: `salt "$(cat /etc/osas26-id)" state.apply manager_org_1.osas26-welcome`{{exec}} then `cat /etc/motd`{{exec}}

(At the HQ table, Uyuni sends them: press **CHECK**, wait for **Promotions**, then `cat /etc/motd`{{exec}})

<details><summary>Your machine is back? Side quests (optional, never ranked)</summary>

- **F6 · The diary's own words**: which word in your minion's log named the fault?
- **X1 · The other fault**: read the real diary of the fault you did NOT get. Which runbook step finds it?
- **D3 · Two files, one truth** (at the HQ table): why the runbook asks `config.get`, not one file.
- Or: Case 2 (below), or help a neighbour: that counts most.

`/root/osas26/quest.sh`{{exec}}
</details>

<details><summary>Case 2 · The server that wouldn't boot (side quest)</summary>

A Uyuni server pod crash-loops with exit code 255. This is all the log says:
```
Executing /docker-entrypoint-init.d/99-cgroupfs-mount.sh...
mount: /sys/fs/cgroup: none already mounted or mount point busy.
```
Suspects: **1** out of memory · **2** the disk is full · **3** something had already mounted `/sys/fs/cgroup` · **4** a wrong database password.
Decide with your neighbour. Akash asks for fingers in the debrief.
(Real output from a Uyuni pull request; fixed in Uyuni 2026.08. The link is in the repo's docs/cases.md after the session.)
</details>
