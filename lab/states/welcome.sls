{#- Geeko Corp crew card = state channel osas26-welcome, file init.sls (replaces v1 welcome.sls + welcome-v2.sls).
    Salt renders this Jinja ON THE MINION, so every check reads a file that the attendee's own actions
    created in THEIR sandbox (catchup.sh 1 counts). No pillar dependency. Keep braces, percent signs and
    hash signs out of the art. Level 3 live edit = change ONLY the quoted text of "order"
    (paste:  find out what happened to the database.  - verify3.sh greps for it).
    LD-3 (brand + kindness): the art is an abstract salt crystal (no creature, no logo), and the card shows a
    SHIFT BADGE, never a rank: the badge is picked by the machine's own id (its hex tail), NEVER by the boxes, so
    no badge can mean "did less" (review fix, LD-3 delta). An empty box says how to fill it later, kindly. #}
{%- set order = "(waiting for orders from HQ...)" %}
{%- set fe = salt['file.file_exists'] %}
{%- set mid = grains['id'] %}
{%- set parts = mid.split('-') %}
{%- set nick = parts[1] if parts | length == 3 else mid %}
{%- set b_blueprint = fe('/root/uyuni.yaml') %}
{%- set b_crew = True %}
{%- set b_incident = fe('/root/.osas26-break') %}
{%- set b_evidence = fe('/root/.osas26-evidence') %}
{%- set badges = ['lamp keeper', 'salt miner', 'key keeper', 'line walker', 'cloud watcher'] %}
{%- set tail = parts[2] if parts | length == 3 else '0' %}
{%- set badge = badges[(tail | int(0, 16)) % 5] %}
{%- macro box(ok) %}{{ '[x]' if ok else '[ ]' }}{% endmacro %}
osas26_motd:
  file.managed:
    - name: /etc/motd
    - contents: |
        ============================================================
                   ______
                  /     /|          GEEKO CORP - SRE CREW CARD
                 /_____/ |          crew: {{ nick }}
                 |     | |          shift badge: {{ badge }}
                 |_____|/           (a salt crystal: HQ runs on Salt)
        ------------------------------------------------------------
         {{ box(b_blueprint) }} Blueprint   {{ "you read HQ's real Uyuni Helm chart" if b_blueprint else 'later: /root/osas26/catchup.sh 1 (it counts)' }}
         {{ box(b_crew) }} Onboarded   Uyuni manages this machine now
         {{ box(b_incident) }} Incident    /root/osas26/break.sh, then fix it
         {{ '[*]' if b_evidence else '[?]' }} Final case  {{ 'your evidence is sealed - verdict soon' if b_evidence else 'SEALED - verdict on the big screen' }}
        ------------------------------------------------------------
         ORDER FROM HQ: {{ order }}
        ------------------------------------------------------------
         {{ mid }} | Uyuni 2026.08 + RKE2, free GitHub runner
         openSUSE.Asia Summit 2026, Yogyakarta
osas26_card:
  file.managed:
    - name: /etc/osas26/card.txt
    - makedirs: True
    - contents: "{{ mid }} badge={{ badge }} blueprint={{ b_blueprint }} incident={{ b_incident }} evidence={{ b_evidence }}"
