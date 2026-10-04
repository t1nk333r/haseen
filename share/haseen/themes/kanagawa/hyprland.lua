local active_border_color = "rgb(dcd7ba)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
    },
  },
})

-- Omarchy also raised terminal opacity here through its o.window helper and
-- "terminal" tag; haseen has neither and keeps terminals opaque, so it is dropped.
