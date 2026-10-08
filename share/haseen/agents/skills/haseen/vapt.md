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
- **The oniomarchy source is opt-in per run.** Items only its repository
  publishes (for example `chirp`, `supersdr`) come from it only with
  `haseen vapt install --with-oniomarchy …`; `--all` never implies it. Approve
  it with `haseen vapt repo-enable oniomarchy` (preview with `--dry-run`, which
  fetches nothing) and inspect with `haseen vapt repo-status`. Tell the user
  that approval imports a signing key into the shared pacman keyring, which
  stays after `haseen vapt repo-disable oniomarchy`. Never add `[oniomarchy]`
  to `/etc/pacman.conf`: haseen then refuses the private source.
- **Provisioning leaves services off.** `services` installs openssh and remmina;
  `anonymity` installs macchanger and tor. Explicit owned-unit service controls
  are separate user requests, not installation hooks. Never enable/init them,
  change a MAC address or launch Tor as a provisioning side effect.
- **Dependencies are not tools.** powershell-bin, xorg-xhost and the Java and
  wxPython runtimes come in only as a selected tool's dependencies.
- **Removal keeps things.** `haseen vapt remove` reverses only haseen's own
  unchanged activation links. Packages, BlackArch keyring trust, repository
  configuration, native environments and reports stay; uninstalling a package
  is a separate, deliberate `pacman -R` the user runs.
- **Never edit `$HASEEN_PATH/layers/vapt/`** to add a tool. A missing tool is
  a change for the haseen repository, reviewed there.

## Installed inventory and explicit usage

`haseen vapt tool-list --json` reports verified installed roots and owned
entrypoints; `--all` adds missing/unknown inventory diagnostics. Never infer
an executable from a package name. Data-only packages have no run action;
multiple entries require explicit `--entry` selection.

Use `haseen vapt tool-help TOOL --entry ENTRY_ID --dry-run` to inspect usage
evidence. Without dry-run it displays a unique owned matching document, or only
a reviewed help-only binding. Missing/ambiguous evidence is a deliberate
refusal: do not work around it by guessing `--help`. `tool-run` displays that
same evidence then opens an ordinary interactive shell, never the selected
program; it has no JSON mode and never prefills a command or starts a backend.

`haseen vapt status --json` preserves 0/1/2 provisioning health.
`haseen vapt doctor --json --dry-run` is observation only, not repair.
`haseen vapt menu --enabled --json` checks the literal merged enable flag of
the optional `haseen.security` surface; it does not enable it. List/status/
doctor/menu never run installed tools, refresh sources or seed settings.
Provisioning seeds VAPT workflow defaults once; never edit that user file for
the user or publish local addresses/selected paths as evidence.


## Explicit local actions

`service-list --json` is observation; start/restart require terminal consent and
revalidated owned `FragmentPath`, stop does not require consent. Exposure remains
unknown; never infer loopback safety from service defaults or enable/preset/init.
`net-listener`, `net-http-server`, `net-file-server` stay foreground. Bind only
literal addresses and unprivileged ports; non-loopback exposure requires consent.
Servers require consent and serve bytes only: no CGI, listing, uploads or fetched
content. The file helper selects one package-owned regular file at `/file`,
never guesses or runs an enumeration script. Doctor capability `enumeration-host`
maps to fixed command `net-file-server`; whitelist capability command verbs.

`net-proxy-ca status/inspect` never changes trust. Trust requires the full typed
fingerprint even with `--yes`; removal preserves foreign/modified anchors.
Never bypass a refusal, configure a browser/proxy, expose private certificate
contents or claim an incomplete updater transaction succeeded. `net-remmina`
launches only the verified client without connection/target/credentials.
Dry-run stays offline and write-free; none of these helpers is an installer hook.
