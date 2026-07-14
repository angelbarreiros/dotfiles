#!/usr/bin/env bash
set -euo pipefail

cwd="$(omarchy-cmd-terminal-cwd 2>/dev/null || pwd)"
session="herdr-$(date +%Y%m%d-%H%M%S-%N)"

exec uwsm-app -- xdg-terminal-exec --dir="$cwd" herdr --session "$session"
