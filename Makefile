# Makefile - two helpers for the repo (PLAN §5.0). Nothing here touches a server.
#   make killercoda   copy attendee/* into the scenario (Killercoda reads files from the scenario directory [L13])
#   make check        offline checks: bash -n, shellcheck, lab/test (CNI), index.json, the scenario copies, server.env
SHELL := /bin/bash
SCEN  := zero-to-uyuni
ASSET_FILES := $(wildcard attendee/*.sh) attendee/server.env attendee/uyuni.yaml.prerendered attendee/manual.adoc.saved

.PHONY: killercoda check
killercoda:
	@mkdir -p $(SCEN)/assets
	@cp -p $(ASSET_FILES) $(SCEN)/assets/
	@# the verify scripts call their neighbours (achieve.sh, probe.sh, game.sh), and catchup.sh calls verify1.sh:
	@# they ship in assets/ too, so /root/osas26 holds the whole set
	@cp -p $(SCEN)/verify1.sh $(SCEN)/verify2.sh $(SCEN)/verify3.sh $(SCEN)/verify4.sh $(SCEN)/assets/
	@cp -p attendee/preinstall.sh $(SCEN)/preinstall.sh
	@echo "scenario assets refreshed from attendee/"

check: killercoda
	@for f in lab/*.sh lab/runner/*.sh lab/test/*.sh clients/*.sh attendee/*.sh $(SCEN)/*.sh; do bash -n "$$f" || exit 1; done; echo "bash -n: ok"
	@shellcheck -S warning -x lab/*.sh lab/runner/*.sh lab/test/*.sh clients/*.sh attendee/*.sh $(SCEN)/*.sh && echo "shellcheck (warnings): ok"
	@bash lab/test/cni.test.sh
	@python3 -m json.tool $(SCEN)/index.json >/dev/null && echo "index.json: valid"
	@git diff --quiet -- $(SCEN) || { echo "the scenario copies changed: commit them"; git status --short -- $(SCEN); }
	@bash lab/lint-server-env.sh attendee/server.env
