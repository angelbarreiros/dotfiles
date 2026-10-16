-- Totoro-inspired window focus colors.
-- This file is loaded after Omarchy's stock and current-theme settings.
local totoro_active_border = {
  colors = { "rgba(bd8ff1ff)", "rgba(e0b1dfff)" },
  angle = 45,
}
local totoro_inactive_border = "rgba(59536faa)"

hl.config({
  general = {
    col = {
      active_border = totoro_active_border,
      inactive_border = totoro_inactive_border,
    },
  },

  group = {
    col = {
      border_active = totoro_active_border,
      border_inactive = totoro_inactive_border,
    },
  },
})
