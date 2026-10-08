# Plan 044: Multiplexer (herdr + tmux), yazi, and the disposable-VM rig

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (user-config seeds and a read-only prerequisite report)
- **Depends on**: 004 024 038
- **Category**: cli
- **Planned at**: 2026-10-05, owner request (items 2, 7, 15)
- **State**: DONE 2026-10-05 — except the VM itself, which stays blocked (plan 014)

## Problem

- haseen had no awareness of any multiplexer or file manager: `grep -rn tmux bin
  share` and `grep -rni 'herdr\|zellij' bin share` were both empty.
- The owner runs `herdr` from the `[omarchy]` repo with a config that mirrors
  the old tmux keymap, and keeps tmux for machines that have no herdr.
- **Plan 014 is blocked** for want of a machine: *"no end-to-end run on a real
  CachyOS machine or VM yet … no qemu, no passwordless sudo and no docker
  group"* (`handoff.md`). The owner's own `t1nk333r/t1nk33r-lab` (MIT) is a
  disposable-VM harness built for exactly this.

## Decision

- **Ship both multiplexers, herdr as the default**, on the same keymap. The
  choice is one bare word in `~/.config/haseen/mux`, seeded once and the user's
  afterwards — the `~/.config/haseen/font` convention (architecture §7).
  `share/haseen/default/shell/functions.sh` (plan 038) resolves
  `HERDR_PANE_ID` → `TMUX` → that file → herdr installed → tmux installed.
- **No colour literals in either multiplexer config.** herdr's
  `[theme] name = "terminal"` and tmux's ANSI names both ride the terminal
  palette the theme pipeline already renders into `current/theme/foot.ini`, so
  they follow `haseen theme set` with no template and no second copy of the
  colours. A test asserts the tmux config contains no `#rrggbb` and no `colourN`.
- **yazi's colours come from a symlinked `theme.toml`**, rendered from the new
  `share/haseen/themed/yazi.toml.tpl` — yazi has no include directive, and a
  flavor would need a directory (`flavor.toml` + `tmtheme.xml`) per theme. This
  is the pattern `10-btop.sh` already uses for btop's `current.theme`. yazi
  merges the file over its own preset, so only the styles a wrong palette would
  make unreadable are in it.
- **Everything plugin-dependent is stripped** from the shipped defaults: tmux's
  TPM block (a dead `run '~/.config/tmux/tpm/tpm'` errors on every start) and
  yazi's `plugin …` binds (dead keys with an error popup), because haseen
  installs neither tpm nor any yazi package.
- **`tools/lab.sh` reports and refuses rather than inventing a guest.** The
  lab keeps the hypervisor in a container (`runner/Dockerfile` carries qemu and
  OVMF; `/dev/kvm` is passed in), so the honest check is "docker daemon
  reachable, or a host qemu". On the reference machine neither holds, and the
  script says so in one sentence and exits 1.

## Rejected

- **`LAB_DISTRO=omarchy` as the guest**: Arch-based and it would run, but it
  installs the `omarchy` and `omarchy-settings` packages haseen refuses by name
  (PKG_DENY, ADR 0001) and ships omarchy-shell. Verifying haseen on top of the
  thing it replaces proves the wrong thing.
- **`./lab sync` to get the checkout into the guest**: it mirrors `$HOME`
  dotfiles *into* the VM, the opposite direction, and would carry the owner's
  real config onto a disposable machine. The wrapper tars this checkout over
  `lab ssh` instead.
- **Failing on `command -v qemu-system-x86_64`**: factually wrong about this
  lab (its own `cmd_doctor` checks `/dev/kvm`, `docker info` and eight host
  tools; qemu is not among them).
- **A `themed/tmux.conf.tpl`**: tmux's status bar needs eight ANSI names the
  terminal palette already supplies, and it would diverge from herdr, which has
  no equivalent mechanism.
- **A yazi flavor directory**, and **the owner's `[flavor] use = "gruvbox-dark"`**:
  the first needs two files per theme, the second pins one palette and requires
  `ya pkg add`, which haseen does not run.
- **`HASEEN_MUX` in `environment.d`** instead of a config file: an env var only
  refreshes at login and cannot be changed without re-importing the systemd user
  environment.

## Verification

- `tests/test-mux.sh` (96) green; `tests/test-seeds.sh` 75/75 unchanged;
  `tests/test-theme.sh` + `tests/test-themes2.sh` green with `yazi.toml` added
  to `THEME_OUTPUTS` and to `THEME_COLOUR_ONLY`.
- **herdr 0.9.3**: `herdr config check` → `config: ok`; because that check
  accepts anything, the config was also validated against herdr's canonical key
  reference fetched from the v0.9.3 tag — 50 keys used, 0 unknown, 0 duplicate
  chords.
- **tmux 3.7_c-1**: `tmux -L haseen-smoke -f …/tmux.conf start-server \; kill-server`
  → exit 0.
- **yazi 26.9.1** (official release binary; yazi is not installed here), under a
  pty with `YAZI_CONFIG_HOME` at the seeded dir: `yazi.toml (4902 chars)`,
  `keymap.toml (1251 chars)`, and the rendered `theme.toml (2798 chars)` all
  parse. Negative control: appending `this is not = = toml` makes the same
  command fail with `TOML parse error at line 94`. With no theme rendered the
  dangling symlink is tolerated and yazi runs on its preset.
- `tools/lab.sh --dry-run` reports the two real blockers (no reachable qemu; the
  lab has no `LAB_DISTRO=cachyos` arm) and exits 1 without cloning or running
  anything.

## Found upstream

herdr 0.9.3's default `swap_pane_up` is `prefix+shift+k`, and both Omarchy's
shipped config and the owner's take that chord for `close_workspace` without
rebinding the swaps — so with `confirm_close = false` the chord destroys the
focused workspace unconfirmed and `swap_pane_up` is dead. haseen's default keeps
the tmux chord for `close_workspace` and binds the four swaps on
`prefix+ctrl+shift+<arrow>`; the duplicate-chord check over all 50 keys now
reports none.

## Open

- **No VM was built.** `install.sh` and `tests/run.sh` have still never run
  inside a guest; plan 014 stays blocked, now with a named rig and two named
  prerequisites instead of "no VM".
- The herdr/tmux layouts from plan 038 were not driven against a live session.
- `herdr` needs a package row in a layer that applies *after* `omarchy-repo`
  (the `base` layer runs before it, so a base row would fall through to the AUR
  build — version 0.9.0+, AGPL-3.0-or-later, a different licence on the same
  name). It is in `share/haseen/layers/desktop/packages.txt`.

## Execution record

`share/haseen/default/{herdr/config.toml,tmux/tmux.conf,yazi/{yazi,keymap}.toml}`,
`share/haseen/themed/yazi.toml.tpl`, `share/haseen/seeds/{65-mux,66-yazi}.sh`,
`tools/lab.sh`, `tests/test-mux.sh`, `tests/test-theme.sh`,
`share/haseen/layers/theme/theme-lib.sh` (`THEME_COLOUR_ONLY`).
