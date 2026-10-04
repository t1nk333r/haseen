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
| [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) | MIT | Avenge Media LLC | plugin manifest shape (compat adapter only) | listed per file header |
| [t1nk333r/omacachy](https://github.com/t1nk333r/omacachy) | own | t1nk33r | dry-run helper contract, ESP bootloader detection, GPU dispatch | listed per file header |
| [gitlab.com/t1nk33r/waydots](https://gitlab.com/t1nk33r/waydots) | own | t1nk33r | BlackArch security layer, package-source rules | listed per file header |

## Reference only (GPL-3.0, **no code copied**)

[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) and
[caelestia-dots/shell](https://github.com/caelestia-dots/shell) are GPL-3.0.
They are design references only: the AI provider adapter split, the
ref-counted "poll only while observed" service pattern and the PAM lock
contexts were re-implemented from their documented behaviour. Copying code
from either would force this repository to GPL-3.0; reviewers reject any diff
that does.
