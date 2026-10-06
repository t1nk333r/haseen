-- Keep only your personal input overrides here.

-- hl.config({
--   input = {
--     kb_layout = "us,dk,eu",
--   },
-- })

-- Flat acceleration, natural scrolling.
hl.config({
  input = {
    accel_profile = "flat",
    touchpad = {
      natural_scroll = true,
    },
  },
})

-- Three-finger swipe up opens the window overview.
hl.gesture({
  fingers = 3,
  direction = "up",
  action = function()
    hl.dispatch(hl.dsp.event("expose.window-overview:toggle"))
  end,
})
