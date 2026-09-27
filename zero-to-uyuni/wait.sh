#!/usr/bin/env bash
# wait.sh - Killercoda intro foreground: show progress, never block the terminal for more than 150 s.
# preinstall.sh writes /tmp/osas26-ready on ANY exit (trap), and join.sh re-runs it if the Salt bundle is missing.
echo 'Preparing your HQ kit...'
for _ in $(seq 150); do [ -f /tmp/osas26-ready ] && break; sleep 1; done
command -v helm >/dev/null && echo 'Kit ready. Read the crew words. Start Level 1 when Akash says so.'
[ -x /usr/bin/venv-salt-minion ] || echo 'Salt part still installing: fine for Level 1; /root/osas26/join.sh finishes it later.'
