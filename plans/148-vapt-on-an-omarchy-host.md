# Plan 148: VAPT provisions on an Omarchy host

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MEDIUM. Two reviewed source rules widen: one distro identity and
  one class of mirror. Omarchy's own repository and its packages are unaffected
  (`ALLOWED` still has no `omarchy`, `forbidden()` still refuses the name and
  the dependency), every other source still refuses an Omarchy mirror, and the
  private source's host still mirrors nothing else. Every case is checked
  against fixtures only.
- **Depends on**: 007 (the layer and its source order), 087 (the reviewed
  identities and the private source), 088 (the read-only workflow), 090 (the
  2026-10-13 audit of both)
- **Category**: vapt
- **Planned at**: 2026-10-31, owner: "the VAPT and security things audit it and
  fix the missing i am starting the VAPT labs tomorrow", then "Yes" to
  supporting an Omarchy host
- **State**: DONE 2026-10-31 (see Verification)

## Problem

An audit of the VAPT and Security surface found the code and its record intact
— `tools/check-docs.sh` OK, shellcheck clean on every VAPT file, `python3 -m
py_compile` clean, and every VAPT suite run in the audit green (`workflow`
139/139, `alpm` 214/214, `confinement-adversarial` 83/83, `net` 237/237,
`services` 140/140, `trust` 227/227, `workflow-adversarial` 141/141). The
manifests agree with `docs/vapt.md`: 25 group files, 204 distinct tool names
(199 in the groups plus the five native-only adapters), and `httpx` still
resolves to BlackArch's package with `/usr/bin/httpx-pd`, never the installed
`python-httpx`.

What is broken is that **none of it works on the host the next lab runs on**.
The audit host is `luna`:

- `/etc/os-release` → `NAME="Omarchy"`, `ID=omarchy`, `ID_LIKE=arch`,
  `BUILD_ID="4.0.6"`.
- `/etc/pacman.d/mirrorlist` is one line,
  `Server = https://stable-mirror.omarchy.org/$repo/os/$arch`, and
  `/etc/pacman.conf` reaches it through `Include` for `[core]`, `[extra]` and
  `[multilib]`.

Two reviewed rules read those two facts as refusals:

1. **The layer refuses the distro.** `share/haseen/layers/vapt/layer.sh:3` was
   `LAYER_DISTROS=(arch cachyos)`, so `haseen vapt install --dry-run --groups
   core` printed `Error: layer vapt does not support distro 'omarchy'
   (supports: arch cachyos)` and exited 1. Nothing has ever been provisioned by
   haseen there: `/var/lib/haseen/vapt/`, `~/.local/state/haseen/vapt/` and
   `~/.config/haseen/vapt/` are all absent. The 59 installed tools and the
   `[blackarch]` stanza in `/etc/pacman.conf` came from somewhere else. This is
   narrower than haseen's own policy: `share/haseen/lib/preflight.sh:27-33`
   says an Omarchy host is supported (haseen replaces it, ADR 0001).
2. **Every Arch repository is refused as a source.** `metadata.py`
   `repository_mirror_safe` refused any mirror URL containing `omarchy`, for
   every source, so `core`, `extra` and `multilib` all reported
   `state: unavailable, reason: source configuration unavailable/refused`
   while `chaotic-aur` and `blackarch` were `safe`.

The consequence, from `haseen vapt doctor --json` on 2026-10-31: of 204
inventory ids, **59 installed, 42 unknown, 103 missing**. The 42 are the tools
that come from Arch's own repositories — `nmap`, `metasploit`, `sqlmap`,
`hydra`, `hashcat`, `john`, `gobuster`, `nikto`, `masscan`, `tcpdump`, `git`,
`go`, `jq`, `ripgrep`, `openssh`, `openssl`, `samba`, `smbclient`, `whois`,
`socat`, `radare2`, `ghidra`, `wireshark-cli`, `zaproxy` and the rest.
`unknown` means no entrypoints, so no panel row, no `tool-help`, no `tool-run`.
All five capabilities were `refused` (`supported adapter package provenance
missing or ambiguous: openbsd-netcat`), and `haseen vapt service-list --json`
refused `ssh` for the same reason.

## What changed

1. **`share/haseen/layers/vapt/layer.sh`** — `LAYER_DISTROS` is
   `(arch cachyos omarchy)`, and the two command paths that repeated the list
   by hand (`layer_precheck`, `vapt_repo`) now call one
   `vapt_distro_supported` helper that reads `LAYER_DISTROS`, so the list and
   its checks cannot drift again. The refusal wording follows `layer_run_apply`
   (`does not support distro 'nixos' (supports: arch cachyos omarchy)`), and
   NixOS stays refused by name.
2. **`share/haseen/layers/vapt/metadata.py`** — a new `ARCH_BASE = ('core',
   'extra', 'multilib')` and `ONIOMARCHY_HOST`. `repository_mirror_safe` now
   requires HTTPS for every source, then refuses any URL naming the private
   source's host, then accepts Arch's own repositories from any remaining host
   and keeps refusing an Omarchy host for every other source.
   `mirror_refusal` repeats that order so its label stays exact (`non-HTTPS`,
   `forbidden Omarchy:`, `oniomarchy self-reference requires review:`).
   Omarchy's own repository is untouched by this: it is absent from `ALLOWED`,
   so `repository_safe` refuses it before the mirror rule and neither
   `emit_snapshot` nor `render_config` ever admits it.

The rule is deliberately narrow: a mirror is transport, not provenance. For
BlackArch, Chaotic-AUR, CachyOS and the private source, the repository *is* the
publisher, so an Omarchy mirror would put Omarchy's own channel in the trust
path. For Arch's `core`, `extra` and `multilib` the publisher is Arch and every
package still has to satisfy the Arch keyring pacman verifies against, so the
mirror host does not decide what is installed.

## Verification

- `tests/run.sh --affected` → **5832/5832, exit 0**. The selection widens to
  32 files because `share/haseen/layers/vapt/layer.sh` and `metadata.py` are
  covered by every VAPT suite; it also picks up `test-core.sh`,
  `test-aipanel.sh` and `test-install-picker.sh`.
- `tests/run.sh tests/test-vapt.sh tests/test-vapt-trust.sh
  tests/test-vapt-oniomarchy.sh` → **908/908**.
- `tests/test-vapt.sh` gains the distro-gate block: an Omarchy `os-release`
  from `tests/fixtures/omarchy-limine-host/etc/os-release` now plans
  `--groups core` and prints no refusal, and a NixOS one still exits 1 with
  `does not support distro 'nixos'` and no `DRYRUN:` line.
- `tests/test-vapt-trust.sh` replaces
  `Omarchy mirror refused as hidden dependency`: an Omarchy mirror of `[extra]`
  is now a usable source and `render_config` renders the host's line as
  written, while the same mirror of `[blackarch]` still refuses with
  `forbidden Omarchy: repository mirror blackarch`.
- `tests/test-vapt-oniomarchy.sh`'s mirror table gains `core`, `multilib`,
  `chaotic-aur`, `cachyos`, an `http://` Omarchy mirror, Omarchy's own
  repository, and an `ALLOWED` assertion. The two cases this plan changes are
  `('extra', 'https://mirror.example.org/omarchy/$arch', False → True)` and the
  `[extra]` row above; `('extra', 'https://pkgs.oniomarchy.com/$arch', False)`
  is kept.
- Against luna's real configuration, `metadata.repository_safe` now returns
  True for `core`, `extra` and `multilib` and still False for `omarchy`;
  `repository_mirror_safe` is True for `stable-mirror.omarchy.org` on the three
  Arch sources and False for `blackarch`, `chaotic-aur` and `cachyos`.
- `tools/lint.sh` OK, `tools/check-docs.sh` OK.
- `tools/secrets.sh` failed the branch's first CI run, and the cause was this
  plan itself: the wording quoted two example home paths literally, which is
  exactly what `tools/secrets.sh`'s `/home/[a-z_][a-z0-9_-]*/` privacy pattern
  looks for in every tracked file and in `git log -p --all`. The sentence no
  longer spells them out. A bare clone of `origin` (48 heads, no `refs/t3/**`,
  the ref set `actions/checkout` with `fetch-depth: 0` produces) then reports
  **0** pattern hits and no gitleaks leak on this branch; its two `gitleaks
  git` findings in `share/haseen/layers/chaotic/layer.sh` and
  `share/haseen/layers/omarchy-repo/layer.sh` are the public key fingerprints
  `main`'s `.gitleaksignore` already lists, which a bare clone cannot read.
  This shared checkout's own `tools/secrets.sh` run still reports 5 pattern
  hits and 9 gitleaks leaks from concurrent agents' `refs/t3/**` checkpoint
  refs; none is in a branch and none is an ancestor of `origin/main`.

## Rejected options

- **Leaving the distro refusal and only widening the mirror rule.** The layer
  would still refuse to provision on the host the lab runs on, which is the
  defect this plan exists to fix.
- **Classifying `ID=omarchy` as `arch` in `preflight_distro`.** That changes
  every layer and every distro-keyed branch in the repository to fix one
  layer's list, and loses the identity the picker reports.
- **Accepting an Omarchy mirror for every source.** BlackArch, Chaotic-AUR,
  CachyOS and the private source publish their own packages; an Omarchy mirror
  of those puts Omarchy's channel in the trust path, which ADR 0001 exists to
  keep out.
- **Accepting the private source's host as a mirror of Arch's repositories.**
  It is admitted only as the reviewed private source, at its one exact root and
  under its 52 reviewed names.
- **Dropping the mirror rule entirely.** `docs/vapt.md` records why it exists:
  a mirror is a runtime dependency, and an unreviewed mirror of a
  self-publishing source is not the reviewed source.
