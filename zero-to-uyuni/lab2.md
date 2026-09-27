# Level 2 · Onboarding: join the fleet

HQ opens its doors when the **countdown on the projector** ends.

Use your **crew name** from your game page (2-12 letters or numbers, not your full name; one crew name per pair: it belongs to both of you):
`/root/osas26/join.sh`{{exec}}

Read the 4 steps it prints. Then look at the projector: your crew's hut calls HQ, and its windows light up when HQ accepts your machine's Salt key.

**Find your line** (Akash will ask):
`cat /etc/venv-salt-minion/minion.d/osas26.conf`{{exec}}

Press **CHECK** when the banner says YOUR SYSTEM.

### Your banner says YOUR OWN HQ?

join.sh knocks on the room's HQ first. No answer? Then **this sandbox runs its own HQ**: a real Salt master, right here.
Same Salt, same lessons. You are its admin, so one job is yours: **accept the key**.

1. Your master's key list. Your minion waits under *Unaccepted Keys*:
`salt-key -L`{{exec}}
2. Check the ID card before you trust it. The two fingerprints must match:
`salt-key -f "$(cat /etc/osas26-id)"; venv-salt-call --local key.finger`{{exec}}
3. Say yes (type **y**):
`salt-key -a "$(cat /etc/osas26-id)"`{{exec}}
4. Your master asks, your minion answers **True**. Not yet? Give it up to 20 seconds, then ask again:
`salt "$(cat /etc/osas26-id)" test.ping`{{exec}}

Press **CHECK**. On the big screen your hut lights up with dotted lines: your own HQ saw it.

<details><summary>Waiting for the room? Side quests (optional, never ranked)</summary>

Your answers stay in your sandbox. Start with `/root/osas26/quest.sh`{{exec}}, then `/root/osas26/quest.sh show R3`{{exec}}.
- **R3 · Your team ticket** · **R4 · Your ID card** · **R5 · The knock log** · **R6 · No doors here**
- **F3 · Trust goes both ways** (compare with HQ's ID card on the big screen) · **F4 · Your name at HQ**
- **D3 · Two files, one truth** · **D5 · Ticket 104: already fixed?**

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
