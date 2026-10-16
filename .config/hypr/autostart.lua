-- Personal startup applications for the Lua-based Omarchy/Quattro session.
-- The legacy autostart.conf is not loaded by hyprland.lua.

local config_hypr = (os.getenv("HOME") or "/home/demper") .. "/.config/hypr"
local state_hypr = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "/home/demper") .. "/.local/state")) .. "/hypr-monitor-profiles"

-- Keep Gmail and WhatsApp running in the hidden scratchpad.
o.exec_on_start(config_hypr .. "/startup-webapps-scratchpad.sh >/dev/null 2>&1 &")

-- Monitor profiles must run from Lua autostart on Omarchy 4; autostart.conf
-- is no longer loaded by the Lua-based Hyprland configuration.
o.exec_on_start("mkdir -p " .. state_hypr .. " && " .. config_hypr .. "/scripts/monitor-profile.sh daemon >>" .. state_hypr .. "/daemon.log 2>&1 &")

-- TUXEDO Control Center's tray frontend.
o.exec_on_start(config_hypr .. "/scripts/start-tuxedo-tray.sh >/dev/null 2>&1")
