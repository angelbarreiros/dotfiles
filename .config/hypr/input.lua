-- Personal input settings migrated from input.conf for Omarchy 4's Lua config.
-- Keep button-area behavior: the local libinput quirk restores the physical
-- right button for this TUXEDO touchpad.

hl.config({
  cursor = {
    -- Keep the pointer at its current global position when the profile
    -- focuses and re-pins workspaces during a monitor transition.
    warp_on_change_workspace = 0,
  },
  input = {
    kb_layout = "es",
    kb_options = "caps:capslock",
    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = false,
      scroll_factor = 0.4,
    },
  },
})

o.window("(Alacritty|kitty)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
