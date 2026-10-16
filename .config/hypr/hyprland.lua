-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Herdr may request activation when an agent finishes or needs permission.
-- Existing sessions and terminal-launched sessions use the Alacritty class.
-- Keep those events from pulling focus away from the current application.
o.window("^(Herdr|Alacritty)$", { focus_on_activate = false })

-- Keep the Chromium Gmail and WhatsApp PWAs in the scratchpad. The window
-- rules place new windows there; the event hook moves them back immediately
-- if a workspace-move binding or drag tries to take them out.
local webapps_scratchpad = "special:scratchpad"
local function is_locked_scratchpad_webapp(window)
  if window == nil then
    return false
  end

  local initial_class = window.initial_class or ""
  return initial_class:match("^chrome%-mail%.google%.com__") ~= nil
    or initial_class:match("^chrome%-web%.whatsapp%.com__") ~= nil
    or initial_class == "ChromiumPWA-Gmail"
    or initial_class == "ChromiumPWA-WhatsApp"
end

o.window("^(ChromiumPWA-(Gmail|WhatsApp)|chrome-(mail\\.google\\.com|web\\.whatsapp\\.com)__.*)$", {
  workspace = webapps_scratchpad .. " silent",
})
o.window({ title = "^(mail\\.google\\.com_|web\\.whatsapp\\.com_).*" }, {
  workspace = webapps_scratchpad .. " silent",
})

hl.on("window.move_to_workspace", function(window, workspace)
  if is_locked_scratchpad_webapp(window) and workspace.name ~= webapps_scratchpad then
    hl.dispatch(hl.dsp.window.move({
      window = window,
      workspace = webapps_scratchpad,
      follow = false,
    }))
  end
end)

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
