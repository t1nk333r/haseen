# Third-party code and references

haseen is MIT licensed. Code adapted from other projects keeps its upstream
copyright notice in the file header **and** is listed here. Add a row in the
same commit that adds the code.

## Code adapted (MIT, compatible)

| Upstream | License | Copyright | What was adapted | Where |
|---|---|---|---|---|
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | theme renderer, colours parser, denylist, git-URL check, theme commands, hook runner | `share/haseen/layers/theme/theme-lib.sh`, `bin/haseen-theme-{set,install,list,current}`, `bin/haseen-hook` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | templates, copied unchanged | `share/haseen/themed/{hyprland.lua,foot.ini,kitty.conf,ghostty.conf,alacritty.toml,btop.theme,neovim.lua}.tpl` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | stock themes, text files only | `share/haseen/themes/{tokyo-night,catppuccin,gruvbox,rose-pine,catppuccin-latte}/`, `tests/fixtures/theme-omarchy-nord/` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | CLI router convention | `bin/haseen` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | agent skill structure; agent skill folder list | `share/haseen/agents/skills/haseen/`, `bin/haseen-ai-skill-install` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | `qs.Commons`/`qs.Ui` plugin API (Style, Color, Util, BarWidget, WidgetButton, BarIconButton, BarIndicator, OpticalGlyph), plugin bar facade, manifest field names | `share/haseen/shell/Compat/Omarchy/`, `share/haseen/shell/Compat/OmarchyHost.qml`, `share/haseen/shell/Compat/Manifest.js` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | bar transparency toggle and wallpaper text-colour script | `bin/haseen-bar-text-color`, `share/haseen/shell/FrameTextColor.qml`, `share/haseen/shell/Bar.qml` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | menu engine and JSONC format; setup steps (DNS, fingerprint, FIDO2), font list | `share/haseen/shell/plugins/haseen.menu/`, `share/haseen/default/menu.jsonc`, `bin/haseen-setup-*`, `bin/haseen-font-list` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | package/AUR pickers, firmware/time/password/restart/refresh scripts, docker DB and Xbox controller steps | `bin/haseen-{install,remove,update,time,password,restart,refresh}`, `share/haseen/lib/catalog.sh`, `share/haseen/default/catalog.json` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | capture, reminder, toggle, hardware, share, disk test, transcode scripts; emoji data and search | `bin/haseen-{capture,reminder,toggle,hardware,share,test}-*`, `bin/haseen-transcode`, `share/haseen/shell/plugins/haseen.emoji/` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | screensaver launcher (ttfx) | `bin/haseen-screensaver` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | 17 more stock themes (text only; kanagawa's hyprland.lua adapted), background next/set; image hashes only (artwork is fetched at runtime, keeps its own terms, never shipped) | `share/haseen/themes/*`, `bin/haseen-theme-bg`, `share/haseen/layers/theme/omarchy-assets.txt` |
| [omacom/omarchy](https://github.com/omacom/omarchy) | MIT | David Heinemeier Hansson | workspaces bar widget; weather glyph table | `share/haseen/shell/plugins/haseen.workspaces/`, `share/haseen/shell/plugins/haseen.weather/Weather.js` |
| [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) | MIT | 2025 Avenge Media LLC | `qs.Common`/`qs.Services`/`qs.Widgets`/`qs.Modules.Plugins` API names (Theme tokens, I18n, SettingsData, PluginService, ToastService, StyledText, StyledRect, DankIcon, PluginComponent), manifest surface derivation | `share/haseen/shell/Compat/Dms/`, `share/haseen/shell/Compat/DmsHost.qml`, `share/haseen/shell/Compat/Manifest.js` |
| [Foxboron/sbctl](https://github.com/Foxboron/sbctl) | MIT | 2020 Morten Linderud | pacman hook Path targets (`contrib/pacman/ZZ-sbctl.hook`); fixture copies of that hook | `share/haseen/layers/secureboot/files/zz-haseen-secureboot.hook`, `tests/fixtures/sb-sdboot-*/usr/share/libalpm/hooks/zz-sbctl.hook` |
| [t1nk333r/omacachy](https://github.com/t1nk333r/omacachy) | own | t1nk33r | dry-run helper contract, ESP bootloader detection, GPU dispatch | listed per file header |
| [gitlab.com/t1nk33r/waydots](https://gitlab.com/t1nk33r/waydots) | own | t1nk33r | package-source rules | listed per file header |

## Reference only (GPL-3.0, **no code copied**)

[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) and
[caelestia-dots/shell](https://github.com/caelestia-dots/shell) are GPL-3.0.
They are design references only: the AI provider adapter split, the
ref-counted "poll only while observed" service pattern and the PAM lock
contexts were re-implemented from their documented behaviour. Copying code
from either would force this repository to GPL-3.0; reviewers reject any diff
that does.
