# Optional VAPT tooling

The `vapt` layer installs security tool groups the user picks, on Arch or
CachyOS. Nothing is installed by default, and nothing it installs is ever
run by it: no tool, no service start or enable, no assessment. The full
contract is `docs/vapt.md` in the haseen repository; `haseen vapt install
--help` prints the usage.

```bash
haseen vapt install --groups sdr,wireless --dry-run   # preview: offline, writes nothing
haseen vapt install --groups sdr,wireless             # provision after the user agrees
haseen vapt install --all --dry-run                   # every group (still no default)
haseen vapt status                                     # 0 complete, 1 not applied, 2 degraded
haseen vapt remove --dry-run                           # only owned activation links
```

## Groups

`core`, `network`, `web`, `passwords`, `ad`, `osint`, `cloud`, `mobile`,
`forensics`, `api`, `htb-cjca`, `htb-cpts`, `htb-cwes`, `htb-cwee`,
`htb-coae`, `sdr`, `wireless`, `privacy`, `anonymity`, `automotive`, `social`,
`reporting`, `ai`, `exploitation`, `services`. The lists are in
`$HASEEN_PATH/layers/vapt/packages/security/<group>.txt`.

## Rules for helping the user

- **Always preview first** with `--dry-run` and show the plan. Run the real
  install only when the user agrees, in a terminal where they can answer
  pacman's prompts (`--yes` skips them); it uses `sudo` itself. Never wrap it
  in `sudo`.
- **Unavailable is an answer, not a bug.** An item no reviewed source
  publishes is reported unavailable and skipped. Do not install it another
  way: no AUR helper, no `pip`/`pipx` by hand, no `makepkg`, no downloaded
  script. `metasploit-mcp` is blocked on purpose (its upstream project is
  ambiguous); `hexstrike-ai` has no reviewed source.
- **No source opt-in exists yet.** oniomarchy's categories shaped the
  `sdr` … `services` groups, but its repository is not a source today. Items
  only it publishes (for example `chirp`, `supersdr`) stay unavailable. Do not
  add `[oniomarchy]` to `/etc/pacman.conf` to work around this: haseen would
  ignore it, and it would reach every other pacman operation. A later opt-in,
  private, signature-required source is planned (plan 083).
- **Services stay off.** `services` installs openssh and remmina; `anonymity`
  installs macchanger and tor. Starting sshd or Tor, or changing a MAC address,
  is the user's explicit decision, done by them, not part of provisioning.
- **Dependencies are not tools.** powershell-bin, xorg-xhost and the Java and
  wxPython runtimes come in only as a selected tool's dependencies.
- **Removal keeps things.** `haseen vapt remove` reverses only haseen's own
  unchanged activation links. Packages, BlackArch keyring trust, repository
  configuration, native environments and reports stay; uninstalling a package
  is a separate, deliberate `pacman -R` the user runs.
- **Never edit `$HASEEN_PATH/layers/vapt/`** to add a tool. A missing tool is
  a change for the haseen repository, reviewed there.
