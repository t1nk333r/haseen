-- haseen autostart. Deliberately short: the shell (haseen-shell.service or
-- dms.service), the keyring and the portals are systemd user units pulled in
-- by graphical-session.target, which uwsm starts. Nothing here launches a bar.
--
-- hyprland.start fires once per session, never on a config reload, so these
-- commands do not pile up when the config is reloaded.

hl.on("hyprland.start", function()
  -- uwsm reaches graphical-session.target (and so starts haseen-shell.service)
  -- once WAYLAND_DISPLAY is in the systemd activation environment. finalize
  -- exports it and signals readiness; repeating it is harmless if Hyprland
  -- already did. Skipped when the session was not started by uwsm.
  hl.exec_cmd("uwsm check is-active >/dev/null 2>&1 && uwsm finalize")
  -- post-boot hooks (~/.config/haseen/hooks/post-boot{,.d/*}); a missing
  -- haseen CLI or hook runner must not break the session start.
  hl.exec_cmd("command -v haseen >/dev/null 2>&1 && haseen hook run post-boot")
end)
