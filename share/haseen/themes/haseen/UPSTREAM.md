# haseen

haseen's own theme and the default for new installs (plan 066). It is a
derivative of HANCORE's Greek Noir; until plan 066 it shipped as
`greek-noir-akane`, which is now an alias for `haseen`.

- **Upstream:** [HANCORE-linux/omarchy-greek-noir-theme](https://github.com/HANCORE-linux/omarchy-greek-noir-theme), MIT (see `LICENSE`).
- **Source:** the owner's installed copy on luna, 2026-10-04.
- **Changes:**
  - `hyprland.lua`: the owner's "akane" variant. The active border is a clockwise wipe driven by Hyprland's `borderangle` animation; gaps are 5 and rounding is 4.
  - `colors.toml`: `mode = "dark"` added; the header names the theme `haseen`.
- **Not shipped:**
  - the backgrounds (the "akane" images have no known licence);
  - the preview image;
  - the files for apps haseen does not theme: mako, walker, waybar, swayosd, hyprlock, steam, heroic, vencord and cava.

  Put your own backgrounds in `~/.config/haseen/backgrounds/haseen/`. `haseen theme bg next` cycles through them.
