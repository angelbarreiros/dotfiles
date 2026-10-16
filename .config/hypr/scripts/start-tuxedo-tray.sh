#!/usr/bin/env bash

set -u

# TUXEDO's system service is enabled separately; this keeps its user tray
# frontend present for every graphical session without starting duplicates.
if pgrep -f '/opt/[t]uxedo-control-center/[t]uxedo-control-center($| --tray)' >/dev/null 2>&1; then
    exit 0
fi

# TUXEDO's Electron tray process must stay attached to the graphical session.
# Launching it through uwsm-app makes it exit shortly after startup on this
# system, before it can remain registered with StatusNotifierWatcher.
exec /opt/tuxedo-control-center/tuxedo-control-center --tray
