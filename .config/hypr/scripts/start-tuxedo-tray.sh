#!/usr/bin/env bash

set -u

# TUXEDO's system service is enabled separately; this keeps its user tray
# frontend present for every graphical session without starting duplicates.
if pgrep -f '/opt/[t]uxedo-control-center/[t]uxedo-control-center($| --tray)' >/dev/null 2>&1; then
    exit 0
fi

exec uwsm-app -- /opt/tuxedo-control-center/tuxedo-control-center --tray
