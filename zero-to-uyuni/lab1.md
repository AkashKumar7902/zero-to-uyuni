# Level 1 · Read HQ's blueprint (the Helm chart)

**First, 10 seconds: link this sandbox to your crew.** Your game page shows this line with your own 4-character crew code. Type it here:

`/root/osas26/crew.sh <your crew code>`

It sends only "done" facts to the big screen, never what you type. No game page? Skip it: everything below works without it.

HQ is a real Uyuni server. It was installed from a **Helm chart**: HQ's blueprint.
Render the real one (release 2026.8.0). *Render = print what the recipe would make, without cooking it.* Nothing gets installed.
(`fqdn` = the server's full name on the network; any name works for reading. `grep` = find lines in a file. Tap any command to run it.)

`cd /root/osas26`{{exec}}

```
helm template demo oci://registry.opensuse.org/uyuni/server-helm --version 2026.8.0 \
  --set global.fqdn=uyuni.example.test > ~/uyuni.yaml
```{{exec}}

Registry slow? `/root/osas26/catchup.sh 1`{{exec}} gives you the same file.

**Q1 · How many storage volumes (PersistentVolumeClaims)?**
`grep '^kind:' ~/uyuni.yaml | sort | uniq -c`{{exec}}

**Q2 · Salt's door: what type is Service `salt`?**
`grep -A14 '^  name: salt$' ~/uyuni.yaml | grep -E 'type:|port:'`{{exec}}

**Q3 · Which container images?**
`grep 'image:' ~/uyuni.yaml | sort -u`{{exec}}

Press **CHECK**. (Not green yet? Type `why`: it says what is missing.)

---

## The final case · your evidence (keep it sealed!)

At 03:12 Lintang, our night engineer, typed a volume name from HQ's **manual** and got `"var-pgsql" not found`.
Is the database gone? Or is something else going on?

1. HQ's real volumes, straight from the blueprint:
`grep -A2 '^kind: PersistentVolumeClaim' ~/uyuni.yaml | grep -o 'name: [a-z0-9-]*' | sort | paste - - -`{{exec}}
2. The manual's list: **printed inside your crew card** (online: [Uyuni docs · Kubernetes guide · Storage](https://www.uyuni-project.org/uyuni-docs/en/uyuni/specialized-guides/kubernetes-guide/server-kubernetes-deployment.html#_storage), ≈ 1.5 MB).
3. Found a difference? Seal it with the name from **HQ's blueprint**: `/root/osas26/claim.sh <name>`
   You get **EVIDENCE CONFIRMED** at once. Then fill the **CASE FILE** box on your crew card.
   (Your game page can seal it too, in the CASE tab: on a phone or a laptop, for anyone in your crew.)

Shh! Don't tell other tables. Stick your **FOUND IT** sticky **inside** your crew card. The verdict comes at the final case.

**No rush:** your evidence stays open until 16:25. Come back to it any time before then.

<details><summary>Stuck? Hint 1</summary>

Search the blueprint for the name Lintang used:
`grep -n 'var-pgsql' ~/uyuni.yaml`{{exec}}
Which line is the volume itself (a PersistentVolumeClaim), and which is only a label inside the pod (a pod = one running program box in Kubernetes)?
</details>

<details><summary>Still stuck? Hint 2: a reviewer's tool</summary>

Put both lists side by side with `diff`:
```
curl -fsSL --max-time 10 https://raw.githubusercontent.com/uyuni-project/uyuni-docs/c4bd1a8b61571ed5f197410391dd6ccd516e9730/en/modules/specialized-guides/pages/kubernetes-guide/server-kubernetes-deployment.adoc -o ~/manual.adoc || cp /root/osas26/manual.adoc.saved ~/manual.adoc
grep '^| `' ~/manual.adoc | grep -o '`[a-z0-9-]*`' | tr -d '`' | sort -u > ~/manual.txt
grep -o 'claimName: [a-z0-9-]*' ~/uyuni.yaml | cut -d' ' -f2 | sort -u > ~/blueprint.txt
wc -l ~/manual.txt ~/blueprint.txt
diff ~/manual.txt ~/blueprint.txt && echo "PERFECT MATCH"
```{{exec}}
A line with `<` is only in the manual. A line with `>` is only in the blueprint.
</details>

<details><summary>Waiting for the room? Side quests (optional, never ranked)</summary>

Pick any. Your answers stay in your sandbox.
- **R1 · Two doors**: what does HQ's blueprint call door 4505? `/root/osas26/quest.sh show R1`{{exec}}
- **R2 · Salt's own disks**: how many of HQ's volumes belong to Salt? `/root/osas26/quest.sh show R2`{{exec}}
- **F1 · HQ's memory map**: where will HQ keep YOUR machine's ID card? `/root/osas26/quest.sh show F1`{{exec}}
- **D1 · Follow a knock** (for crews who know Kubernetes): `/root/osas26/quest.sh show D1`{{exec}}

All quests: `/root/osas26/quest.sh`{{exec}} · Helping a neighbour counts more than any quest.
</details>
