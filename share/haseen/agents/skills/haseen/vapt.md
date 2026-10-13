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
  publishes under its own name or a reviewed alias is reported unavailable
  and skipped. Do not install it another way: no AUR helper, no `pip`/`pipx`
  by hand, no `makepkg`, no downloaded script. `metasploit-mcp` is blocked on
  purpose (its upstream project is ambiguous); `hexstrike-ai` has no reviewed
  source.
- **The oniomarchy source is opt-in per run.** Items only its repository
  publishes (for example `chirp`, `supersdr`) come from it only with
  `haseen vapt install --with-oniomarchy …`; `--all` never implies it. Approve
  it with `haseen vapt repo-enable oniomarchy` (preview with `--dry-run`, which
  fetches nothing) and inspect with `haseen vapt repo-status`. Tell the user
  that approval adds a signing key to the shared pacman keyring, which stays
  after `haseen vapt repo-disable oniomarchy`. Never add `[oniomarchy]` to
  `/etc/pacman.conf`: haseen then refuses the private source.
- **Provisioning leaves services off.** `services` installs openssh and
  remmina; `anonymity` installs macchanger and tor. Never enable or start
  them, change a MAC address or launch Tor as a side effect.
- **Dependencies are not tools.** powershell-bin, xorg-xhost and the Java and
  wxPython runtimes come in only as a selected tool's dependencies.
- **Removal keeps things.** `haseen vapt remove` reverses only haseen's own
  unchanged activation links. Packages, keyring trust, repository
  configuration, native environments and reports stay; uninstalling a
  package is a separate `pacman -R` the user runs.
- **Never edit `$HASEEN_PATH/layers/vapt/`** to add a tool. A missing tool is
  a change for the haseen repository, reviewed there.

## Installed inventory and usage

`haseen vapt tool-list --json` reports verified installed roots and owned
entrypoints; `--all` adds missing items. Never infer an executable from a
package name. Data-only packages have no run action; several entries need an
explicit `--entry`.

`haseen vapt tool-help TOOL --entry ENTRY_ID --dry-run` shows the usage
evidence. Without dry-run it prints a unique owned matching document (man
page translations count as one page), or runs only a reviewed help-only
binding. A missing or ambiguous document is a deliberate refusal: do not
guess `--help`. `tool-run` shows the same document, then opens an ordinary
interactive shell, never the selected program.

`haseen vapt status --json` keeps the 0/1/2 provisioning health;
`haseen vapt doctor --json --dry-run` observes and never repairs.
`haseen vapt menu --enabled --json` reports the literal merged enable flag of
the optional `haseen.security` panel and enables nothing. None of these runs
an installed tool, refreshes a source or seeds settings. Never edit the
user's `~/.config/haseen/vapt/workflow.json` for them or publish local
addresses or selected paths.

## Explicit local actions

- Services: `service-list --json` observes. `service-start` and
  `service-restart` ask in a terminal; `service-stop` does not. Exposure is
  always unknown: never infer loopback safety or enable, preset or init a
  unit.
- `net-listener`, `net-http-server` and `net-file-server` stay in the
  foreground, bind literal addresses and unprivileged ports, and serve bytes
  only (no CGI, listing, uploads or fetched content; the file helper serves
  one package-owned file at `/file`). A server or a non-loopback listener
  needs consent typed at an interactive terminal: `--yes` and piped input
  are refused, so let the user run them. Requests whose Host is not
  `localhost` or a local address get 421. Doctor's `enumeration-host` maps to
  `net-file-server`; whitelist capability command verbs.
- `net-proxy-ca status`/`inspect` never change trust. `trust` needs the full
  typed fingerprint even with `--yes`; `remove` keeps foreign or modified
  anchors. An interrupted trust (state `unknown`, transaction `pending`) is
  finished by `trust` with the same certificate or rolled back by `remove`.
  Never configure a browser or proxy, expose certificate contents or claim an
  incomplete update succeeded.
- `net-remmina` opens only the verified client, with no target or
  credentials.

Every dry-run is offline and write-free; none of these helpers is an
installer hook.

## Optional Security workstation panel

`haseen.security` ships disabled and panel-only. Enable it only on the
user's explicit request with `haseen plugin enable haseen.security`; open it
with `haseen shell ipc panel toggle haseen.security` or Setup → Security →
VAPT workstation. Pages: Overview, Tools, Services, Local actions. Opening and
selecting inspect; nothing runs during discovery.

Actions use fixed whitelisted verbs and argv, never shell text; service
actions carry the displayed unit and FragmentPath, and a mismatch refuses.
The panel never passes `--yes`. Everything except the remote desktop client
opens in a terminal, which asks before a service start or restart, a local
server, a non-loopback listener or a CA trust change; Stop and the client
have no prompt. A launch reports "completion has not been checked", never
success; status changes only on Refresh or reopen. Forms, paths, addresses
and certificates stay in memory. The menu answers the Security guard from the
shell's own flag, and disabled Security providers read nothing. Do not bypass
enablement or a CLI refusal. Offscreen tests are not screen-reader
verification.
