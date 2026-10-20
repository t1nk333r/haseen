# UPSTREAM — haseen.settings

`haseen.settings` is a port of the plugin manager of **shell-settings**, MIT,
Copyright (c) AyushKr2003. `LICENSE` here is the upstream licence, unchanged.

| | |
|---|---|
| Upstream | https://github.com/AyushKr2003/shell-settings (Omarchy plugin `shell.settings`); the fork records no upstream commit |
| Ported from | the owner's fork `t1nk33r.settings` 1.1.0 (plugin deletion as one transaction with a summary, hosted-widget handling, a real `shell.json` writer), luna yadm last `88c47f7`; the IO copies are identical |
| Fork file hashes (sha256, first 12) | `SettingsPanel.qml` `e69546cf4a60`, `components/DynamicSettingsForm.qml` `bf20cdd2bc97` |
| Ported | 2026-10-20, plan `plans/096-adopt-tools-forks.md` |

## What was kept

The Plugins section: every plugin with its origin and state, search and
filters, enable/disable, a form generated from a plugin's declared
settings, and deletion of one plugin or a selection in one process that runs
to the end and reports each name.

## What changed

- Rows come from the running shell's registry (`Haseen/Plugins.qml`), not
  `omarchy-shell` IPC and `bin/plugin-inventory`; the form reads haseen's
  manifest schema (`{type, default, description}`).
- Every write goes through haseen's CLI: `haseen plugin enable|disable`,
  `haseen plugin settings` (one request per save; Reset drops a key) and
  `haseen plugin uninstall`. The fork's `bin/settings-write`,
  `settings-purge`, `settings-remove` and `settings-move` (Python writers of
  Omarchy's `shell.json`) are not ported.
- Deletion is offered only for a directory directly under
  `~/.config/haseen/plugins`; built-ins and `~/.config/omarchy/plugins`,
  `~/.config/DankMaterialShell/plugins` never are (and the CLI refuses them).

## What was dropped, and where haseen already does it

- Bar editor (position, transparency, drag between sections): the bar's
  arrange mode and `haseen bar …` (architecture 5.3).
- Idle and lock timings: `haseen setup idle`, Setup › Idle and Suspend.
- Install from a git URL or a folder: `haseen plugin install`, Setup ›
  Plugins › Add Plugin.
- Drawer move/eject (`t1nk33r.nook`): haseen's overflow panel.
- Rescan: the registry watches the plugin directories itself.
