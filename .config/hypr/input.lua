-- Personal input settings migrated from input.conf for Omarchy 4's Lua config.

hl.config({
  input = {
    kb_layout = "es",
    kb_options = "caps:capslock",
    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,
    touchpad = {
      natural_scroll = true,
      scroll_factor = 0.4,
    },
  },
})

o.window("(Alacritty|kitty)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
