# Level 3 · Orders from HQ

Do nothing yet. Watch this terminal: HQ (Uyuni) will talk to you through Salt.
If your prompt looks odd, press **Enter**.

When the message says so, open your screen card (the crew card HQ writes on your machine):
`cat /etc/motd`{{exec}}
(motd = message of the day: the text Linux shows at login)

Does Uyuni know whether you finished Level 1? Look at your card.

Your crew's hut never lit up on the big screen? Ask a helper, then `touch /tmp/osas26-skip3`{{exec}} and watch with your neighbour.

Press **CHECK**.

<details><summary>Your banner said YOUR OWN HQ? Your steps are here.</summary>

Akash sends the room's orders from Uyuni. Your master sends yours: the same two kinds of order.

1. A **remote command**, as root:
`salt "$(cat /etc/osas26-id)" cmd.run '/root/osas26/hq-say.sh welcome'`{{exec}}
2. A **state**: the recipe of your crew card. Apply it, then read the card:
`salt "$(cat /etc/osas26-id)" state.apply manager_org_1.osas26-welcome`{{exec}}
`cat /etc/motd`{{exec}}
3. When Akash changes the room's order, change yours: edit the order line in your recipe.
`sed -i 's/(waiting for orders from HQ...)/find out what happened to the database./' /srv/salt/manager_org_1/osas26-welcome/init.sls`{{exec}}
Vote with the room first. Then look at your card: `cat /etc/motd`{{exec}}
Apply the recipe again, and look once more:
`salt "$(cat /etc/osas26-id)" state.apply manager_org_1.osas26-welcome`{{exec}}
`cat /etc/motd`{{exec}}

Does your master know whether you finished Level 1? Look at your card. Press **CHECK**.
</details>

<details><summary>Waiting for the room? Side quests (optional, never ranked)</summary>

- **R7 · HQ's diary entry**: which two kinds of order reached your machine?
- **F5 · The recipe asks your machine** · **F7 · Up and down** · **F2 · Where orders live**
- **D4 · What is in your highstate?** · **D2 · Drift and repair** (after your card arrives)

`/root/osas26/quest.sh`{{exec}} · Helping a neighbour counts more than any quest.
</details>
