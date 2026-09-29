# Level 2 · Onboarding: join the fleet

Today **your sandbox runs its own HQ**: a real Salt master, right here, next to your machine.
Same Salt, same lessons, and you are its admin.

Wait for the **countdown on the projector**. At zero, run the join command.
Use your **crew name** from your game page (2-12 letters or numbers, not your full name; one crew name per pair: it belongs to both of you):
`/root/osas26/join.sh`{{exec}}

Read the 4 steps it prints.

**Find your line** (Akash will ask):
`cat /etc/venv-salt-minion/minion.d/osas26.conf`{{exec}}
`activation_key` is read only by Uyuni: at the front table it puts your machine in team osas26-fleet. Your own master ignores it.

### Your banner says YOUR OWN HQ? Good: that's today's plan

Your minion is waiting for its master. You are the admin, so one job is yours: **accept the key**.

1. Your master's key list. Your minion waits under *Unaccepted Keys*:
`salt-key -L`{{exec}}
2. Check the ID card before you trust it. The two fingerprints must match:
`salt-key -f "$(cat /etc/osas26-id)"; venv-salt-call --local key.finger`{{exec}}
3. Say yes (type **y**):
`salt-key -a "$(cat /etc/osas26-id)"`{{exec}}
4. Your master asks, your minion answers **True**. Not yet? Give it up to 20 seconds, then ask again:
`salt "$(cat /etc/osas26-id)" test.ping`{{exec}}
(Why up to 20 s? A waiting minion knocks again every 10 seconds: side quest R5.)

Press **CHECK**. On the big screen your hut lights up, with no line to HQ: your own master trusts it.

<details><summary>Sitting at the HQ table (the front table)? Your steps are here.</summary>

Your sandbox joins Uyuni, the HQ on the projector. At zero:
`/root/osas26/join.sh --hq`{{exec}}
Your banner says YOUR SYSTEM. HQ's accept script says yes to osas26- names: your crew's hut gets a ring and a line to HQ when HQ accepts your machine's Salt key.
Press **CHECK** when the banner says YOUR SYSTEM.
Nothing on the big screen after 3 minutes? Ask a helper, or give your sandbox its own HQ (about 30 seconds): `/root/osas26/join.sh --solo`{{exec}}
If Uyuni HQ says no or goes quiet, your sandbox does this by itself, with a yellow note in the terminal.
Then follow the 4 steps above.
</details>

<details><summary>Waiting for the room? Side quests (optional, never ranked)</summary>

Your answers stay in your sandbox. Start with `/root/osas26/quest.sh`{{exec}}, then `/root/osas26/quest.sh show R3`{{exec}}.
- **R3 · Your team ticket** · **R4 · Your ID card** · **R5 · The knock log** · **R6 · Two jobs, one machine**
- **F3 · Trust goes both ways** (your machine checks its master's ID card too) · **F4 · Your name at HQ**
- **D5 · Ticket 104: already fixed?** · **D3 · Two files, one truth** (at the HQ table: it reads a file only Uyuni writes)

Helping a neighbour counts more than any quest.
</details>

<!-- LD-6: tickets 101 and 102 are the reserve final cases (3B = D2, 3C = N2). If claim.sh's CASE switches to D2 or N2,
     remove that ticket from the block below in the SAME push, and never turn it into a side quest. -->
<details><summary>Waiting for the room? The HQ ticket queue (optional, never ranked)</summary>

Each ticket: run the command, compare with the manual. Disagree? Note it on your crew card.
- **101 · The path to nowhere.** The manual (Preparation section) says older blueprints live here. Does it work?
`helm show chart oci://registry.opensuse.org/systemsmanagement/uyuni/snapshots/2026.08/opensuse_tumbleweed/uyuni/server-helm --version 2026.8.0`{{exec}}
Now try `charts` instead of `opensuse_tumbleweed`.
- **102 · Which Helm?** The manual's checklist says "Helm v3". What did *you* use in Level 1? `helm version --short`{{exec}} Bug, or an old version? You decide.
- **103 · Two maps disagree.** `helm show readme oci://registry.opensuse.org/uyuni/server-helm --version 2026.8.0 | grep -n 'db-cert'`{{exec}} Compare with the manual's "TLS setup" section.
- **104 · Already fixed?** `helm show values oci://registry.opensuse.org/uyuni/server-helm --version 2026.8.0 | grep -n 'tab will'`{{exec}}
Then check the newest version: `curl -s https://raw.githubusercontent.com/uyuni-project/uyuni/master/containers/server-helm/values.yaml | grep -n 'By default the ta'`{{exec}}
</details>
