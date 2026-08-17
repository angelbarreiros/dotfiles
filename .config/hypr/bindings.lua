-- Personal keybindings migrated from bindings.conf for Omarchy 4's Lua config.

local function replace(keys, description, dispatcher, options)
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

-- Remove v4 preinstalled app/webapp bindings for applications removed during
-- the cleanup. Keep the repository-owned bindings below as the source of truth.
for _, keys in ipairs({
  "SUPER + SHIFT + O",       -- Obsidian
  "SUPER + SHIFT + ALT + M",  -- Cliamp
  "SUPER + SHIFT + A",        -- ChatGPT
  "SUPER + SHIFT + ALT + A",  -- Grok
  "SUPER + SHIFT + C",        -- HEY calendar
  "SUPER + SHIFT + E",        -- HEY mail
  "SUPER + SHIFT + ALT + E",  -- HEY new mail
  "SUPER + SHIFT + Y",        -- YouTube
  "SUPER + SHIFT + ALT + G",  -- WhatsApp default webapp
  "SUPER + SHIFT + CTRL + G", -- Google Messages
  "SUPER + SHIFT + P",        -- Google Photos
  "SUPER + SHIFT + X",        -- X
  "SUPER + SHIFT + ALT + X",  -- X post
}) do
  hl.unbind(keys)
end

-- Application bindings.
replace("SUPER + RETURN", "Herdr", "~/.config/hypr/scripts/launch-or-focus-herdr.sh")
replace("SUPER + ALT + RETURN", "Herdr", 'uwsm-app -- xdg-terminal-exec --dir="$(omarchy-cmd-terminal-cwd)" herdr')
replace("SUPER + SHIFT + RETURN", "Browser", "omarchy-launch-browser")
replace("SUPER + SHIFT + F", "File manager", "uwsm-app -- nautilus --new-window")
replace("SUPER + ALT + SHIFT + F", "File manager (cwd)", 'uwsm-app -- nautilus --new-window "$(omarchy-cmd-terminal-cwd)"')
replace("SUPER + SHIFT + B", "Browser", "omarchy-launch-browser")
replace("SUPER + SHIFT + ALT + B", "Browser (private)", "omarchy-launch-browser --private")
replace("SUPER + SHIFT + M", "Music", "omarchy-launch-or-focus spotify")
replace("SUPER + SHIFT + W", "WhatsApp", "~/.config/hypr/scripts/launch-or-focus-pwa-whatsapp.sh")

-- Custom overrides.
replace("SUPER + SHIFT + N", "Notification Center", "omarchy-shell notifications showHistory")
replace("SUPER + CTRL + M", "Toggle notification silencing", "omarchy-toggle-notification-silencing")
replace("SUPER + B", "Web browser", "chromium")
replace("SUPER + L", "Lock session", "loginctl lock-session")
replace("SUPER + W", "Close window (webapps to scratchpad)", "~/.config/hypr/close-active-window.sh", {
  allow_input_capture = true,
})
replace("SUPER + DELETE", "Force close window", "~/.config/hypr/force-close-active-window.sh")

-- Keep the Omarchy 3 menu muscle memory after the Omarchy 4 migration.
replace("SUPER + SPACE", "Apps menu", "omarchy-menu toggle apps")
replace("SUPER + ALT + SPACE", "Omarchy menu", "omarchy-menu toggle")

-- Move windows to workspaces silently, without following them.
for index = 1, 10 do
  local code = "code:" .. (index + 9)
  local keys = "SUPER + SHIFT + " .. code
  hl.unbind(keys)
  o.bind(keys, "Move window to workspace " .. index, hl.dsp.window.move({
    workspace = tostring(index),
    follow = false,
  }))
end

replace("SUPER + SHIFT + S", "Move window to scratchpad", hl.dsp.window.move({
  workspace = "special:scratchpad",
  follow = false,
}))

replace("SUPER + M", "Gmail", "~/.config/hypr/scripts/launch-or-focus-pwa-gmail.sh")
