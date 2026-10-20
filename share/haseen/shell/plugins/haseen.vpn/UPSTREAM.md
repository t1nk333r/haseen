# UPSTREAM — haseen.vpn

`haseen.vpn` is a port of **omarchy-vpn**, MIT, Copyright (c) 2026 Justin
Köstinger (`LICENSE`), with the NordVPN plugin of guiestrela folded in as a
fifth backend, MIT, Copyright (c) 2026 Guilherme Estrela (`LICENSE.nordvpn`).

| | |
|---|---|
| Upstream | https://github.com/jkoestinger/omarchy-vpn (`jkoestinger.vpn`), base `1d61a54ed8e4a1c5fd6083503bf7d5ce0699fbf8`; https://github.com/guiestrela/omarchy-norvpn-plugin at `7ad62aa2099efc55ea9c333372009e497a9cd82d` |
| Ported from | the owner's fork `t1nk33r.vpn` 1.4.1-t1nk33r.1, luna yadm last `88c47f7`; the IO copies are identical |
| Fork file hashes (sha256, first 12) | `VpnController.qml` `18a056ea85e0`, `Panel.qml` `e9b8128bba1c`, `model/Shared.js` `10e06af188ae`, `model/NetworkManager.js` `7c04dd6b997b` |
| Ported | 2026-10-20, plan `plans/096-adopt-tools-forks.md` |

## What changed

- **Unchanged:** `model/*.js` and their tests (113 cases), apart from a notice.
- **Backends:** `command -v` instead of `omarchy-cmd-present`; every Timer
  marked; the post-command re-reads every 2 s instead of 1.5 s.
- **Controller → `Service.qml`** (role `vpn`): one instance for all bars; IPC
  target `haseen.vpn`; the exclusive-connect wait reads every 2 s for up to
  10 s (was 700 ms); the refresh is a literal 5 s sampler acting every
  `refreshIntervalSec`; credentials prompts open in `haseen config terminal`.
- **Panel:** a native lazy panel; the fork's five-section keyboard cursor is
  reduced to the target list (j/k, Enter, Tab tool, Space switch, r, /).
- **OpenConnect helper:** `bin/haseen-vpn-openconnect`
  (`HASEEN_OPENCONNECT_AUTH_DIALOG`). Privilege stays with each tool's
  daemon and NetworkManager's polkit rules; nothing runs as root.
