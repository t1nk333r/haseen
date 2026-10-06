-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

local omarchy_monitor_scale = 1.25

hl.env("GDK_SCALE", "1")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
