# Plan 073: the shell layer installs Helium, with the Cairn extension

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (one more package in the shell layer, a user-level file Helium reads at start, a download checked by SHA-256 and extension ID)
- **Depends on**: 017 070
- **Category**: shell, apps
- **Planned at**: 2026-10-07, owner request (io): "When installing the shell, the Helium browser must be installed, and this extension with it: https://github.com/t1nk333r/cairn"
- **State**: DONE 2026-10-07 (`tests/test-helium-cairn.sh`, `tests/test-shell.sh`; the mechanism proven on Helium 0.18.3.1 from the Chaotic-AUR package, run from scratch)

## What changes

- `share/haseen/layers/shell/packages.txt`: `aur:helium-browser-bin`.
  `pkg_install_aur` takes it from Chaotic-AUR (0.18.3.1-1 there,
  `pacman -Si chaotic-aur/helium-browser-bin`), and from the AUR only as the
  last resort. The shell layer requires `desktop`, which requires `chaotic`.
  The owner's approval is recorded in AGENTS.md.
- `share/haseen/lib/cairn.sh`: Cairn's pinned release, its download and
  checks, the hand-over to Helium, update and status.
- `bin/haseen-setup-cairn`: `haseen setup cairn [install|status|update]`.
- `layers/shell/layer.sh`: `layer_apply` runs `cairn_install` after the
  packages. A failed download warns and leaves the rest of the layer applied.
  `layer_status` checks `helium-browser-bin` and Cairn. `layer_remove` keeps
  both (see "Never removed").

Cairn is the owner's extension, AGPL-3.0. haseen ships none of its code: the
release's `.crx` is downloaded at install time.

## The mechanism: Chromium's per-user external extensions

haseen writes the file
`~/.config/net.imput.helium/External Extensions/bddeidknhkokohcgdkpgdmlppgfkblig.json`:

```json
{
  "external_crx": "~/.local/share/haseen/extensions/cairn/0.1.1/cairn-0.1.1.crx",
  "external_version": "0.1.1"
}
```

The real file holds the absolute path. Helium installs the `.crx` on its next
start. Cairn comes up enabled, as an external extension, without developer
mode. It is updated when `external_version` rises, and its settings are kept.

### Helium's paths (the 0.18.3.1 binary)

`strings -n 6 /opt/helium-browser-bin/helium` from the extracted package lists:

- `net.imput.helium`: the user data directory, `$XDG_CONFIG_HOME/net.imput.helium`.
  io's own Helium profile is `~/.config/net.imput.helium/Default`.
- `External Extensions`: the per-user directory. Chromium reads it next to
  the profiles, so every Helium profile gets Cairn.
- `/usr/share/chromium/extensions`: the system-wide directory.
- `/etc/chromium/policies`: the policy directory.

Helium shares the system-wide extensions directory and the policy directory
with Chromium, which is also one of haseen's default browsers (plan 070). io
proves the policy path: `/etc/chromium/policies/managed/color.json` (Omarchy's
theme colour) colours Helium's new tab page in a headless screenshot.

The binary also carries `external_crx`, `external_version`,
`external_update_url` and `extensions.external_uninstalls`. Helium's wrapper,
`/usr/bin/helium-browser`, adds flags from `/etc/helium-browser-flags.conf`,
`~/.config/helium-browser-flags.conf` and `$HELIUM_USER_FLAGS`.

### Proof on the real browser, outside io's system

The package is from io's pacman cache:
`/var/cache/pacman/pkg/helium-browser-bin-0.18.3.1-1-x86_64.pkg.tar.zst`, the
file `pacman -S` fetches from Chaotic-AUR. It was extracted into scratch. Nothing
under `/usr`, `/etc` or io's `~/.config` was touched.

1. `haseen setup cairn` ran from this tree with `HOME`, `XDG_CONFIG_HOME` and
   `XDG_DATA_HOME` in scratch. It downloaded the real
   `cairn-0.1.1.crx`, checked it, and wrote the file above. A second run
   printed `Cairn 0.1.1 is already handed to Helium`.
2. The scratch Helium ran as
   `helium --headless=new --user-data-dir=$XDG_CONFIG_HOME/net.imput.helium --no-first-run --disable-gpu about:blank`.
   Headless Helium's default directory is `net.imput.helium-headless`, so the
   directory is named explicitly.
3. `Default/Preferences` then held
   `extensions.settings.bddeidknhkokohcgdkpgdmlppgfkblig`:
   - `location: 2` (`kExternalPref`);
   - `disable_reasons: []`, so the extension is enabled;
   - `from_webstore: false`;
   - `manifest.name: "Cairn"`, `manifest.version: "0.1.1"`;
   - `path: "bddeidknhkokohcgdkpgdmlppgfkblig/0.1.1_0"`.

   The installed copy is `Default/Extensions/bddeidknhkokohcgdkpgdmlppgfkblig/0.1.1_0/`.
   `Default/Service Worker/ScriptCache` holds Cairn's background worker, so it
   ran. `haseen setup cairn status` then said `ok: Cairn 0.1.1 in Helium`.
4. With the JSON file deleted, the next start uninstalled Cairn: the
   extension directory and its `location` and `path` settings were gone. That
   is why haseen never deletes the file.

Helium logged only `Extension bddeidknhkokohcgdkpgdmlppgfkblig can not be
updated`, because the manifest has no `update_url`. ungoogled-chromium's
`extension-mime-request-handling` flag is not needed. It governs `.crx` files
downloaded from web pages, not external extensions.

The chrome://extensions page was not checked: a headless `--screenshot` of a
`chrome://` URL renders the new tab page. A nested Hyprland session was not
needed, because Preferences, the extension directory and the service worker
cache show the install. On io, the real check is to restart Helium after
`haseen setup cairn` and open chrome://extensions.

### The release, pinned

The pin is in `lib/cairn.sh`:

- `CAIRN_VERSION=0.1.1`, released 2026-09-03 (GitHub API `releases/latest`).
- `CAIRN_SHA256=030d8b3c…5d6f7`, the SHA-256 of `cairn-0.1.1.crx`.
  `sha256sum` of the download matches the asset's `digest` in the API.
- `CAIRN_ID=bddeidknhkokohcgdkpgdmlppgfkblig`.

The ID comes from the CRX3 header of `cairn-0.1.1.crx`. The header is 581
bytes and holds one RSA proof with a 294-byte key, plus the signed header data.
The key's SHA-256, first 16 bytes, spelt a-p, gives the ID, and it equals the
signed `crx_id`. `chrome.zip` has no `key` in its manifest. Loaded unpacked, it
would get a path-derived ID instead.

`cairn_fetch` downloads to a hidden `.part` file over HTTPS with a size cap.
It then checks:

- the SHA-256, against the pin, or against GitHub's digest for `update`;
- the ID the file proves: `cairn_crx_id` parses the CRX3 protobuf in bash with
  `od`, and accepts the signed `crx_id` only when a key in the header hashes
  to it.

Either mismatch deletes the file, refuses, and leaves the old state. Helium
checks the signature itself when it installs. The ID check keeps a different
extension from landing under Cairn's file name.

### `haseen setup cairn`

- `install` (the default, and the shell layer's step): the pinned release.
  A later release already deployed stays, so a re-apply never downgrades.
  When the file and the `.crx` already match, nothing is written or downloaded.
- `update`: reads `releases/latest`, takes the asset `cairn-<tag>.crx` and its
  `digest`, and deploys it. With no digest it refuses: haseen never deploys an
  unchecked download. The directories of older versions are removed once the
  file points at the new one. A dry run still reads the API, which is a read,
  so the plan can name the version. It downloads and writes nothing.
- `status`:
  - Cairn is in Helium (an `Extensions/<id>/` directory in any profile);
  - or it is handed over and waits for the next start;
  - or it is missing (no file, or a deleted `.crx` before Helium took it);
  - or it was removed in Helium (`extensions.external_uninstalls` lists the ID).
    Chromium then does not reinstall an external extension, and haseen leaves it.

### Never removed

Deleting the external file uninstalls Cairn and its settings, which hold the
user's backup targets (step 4 above). So `haseen layer remove shell` keeps it,
and Helium as well. A user who wants Cairn gone removes it in Helium's
chrome://extensions, and Helium remembers that choice.

## Rejected options

- **System-wide `/usr/share/chromium/extensions/<id>.json`** (option a,
  system-wide). It needs root, and Chromium reads the same directory, so
  Chromium would get Cairn too. The `.crx` would have to live in a root-owned
  path. The per-user directory does the same job with no root. It is
  Helium-only and was proven above.
- **Managed policy `ExtensionInstallForcelist`** in
  `/etc/chromium/policies/managed/` (option b). It applies to Chromium as well,
  since the directory is shared. It forces the extension on: the user cannot
  disable or remove it, and Helium shows "installed by your administrator". It
  also needs an update manifest over HTTPS, and Cairn's releases have none:
  their `updates.json` covers Firefox only.
- **`--load-extension=` through a haseen override of `helium.desktop`**
  (option c). Helium shows a developer-mode warning, and launches outside the
  desktop file (the wrapper, `xdg-open`, the default-browser path) lose the
  extension. The ID derives from the unpacked path, so Cairn's storage would
  be lost when the path changes.

## Proposed for the cairn repository (not done here)

Helium could update Cairn by itself if Cairn published a Chromium update
manifest. haseen has not pushed anything to cairn. The change would be:

1. Add `"update_url": "https://github.com/t1nk333r/cairn/releases/latest/download/updates.xml"`
   to the Chromium build's `manifest.json`. This needs the `.crx` signed with
   the same key, so the ID stays `bddeidknhkokohcgdkpgdmlppgfkblig`.
2. Have the release workflow attach an `updates.xml` asset beside the `.crx`:

   ```xml
   <?xml version='1.0' encoding='UTF-8'?>
   <gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
     <app appid='bddeidknhkokohcgdkpgdmlppgfkblig'>
       <updatecheck codebase='https://github.com/t1nk333r/cairn/releases/download/vX.Y.Z/cairn-X.Y.Z.crx' version='X.Y.Z' />
     </app>
   </gupdate>
   ```

   `releases/latest/download/<name>` redirects to the newest release's asset.

With that in place, an external extension also follows the `update_url` of its
manifest, and `haseen setup cairn update` becomes optional. The same manifest
would make option (b) possible, though (b) stays rejected for the reasons above.

## Tests

`tests/test-helium-cairn.sh` (63 checks). curl is a stub that serves files
from the sandbox. The fake `.crx` files are built from a test key.

- **The ID.** It is read from the key, and a header naming another key's ID
  proves nothing. A zip is not a crx. The pin is Cairn's real version, SHA-256
  and ID.
- **Dry run.** It plans the download, the checks and the external file with
  the right path and version. It runs no stub and writes nothing under `$HOME`.
- **Refusals.** A SHA-256 mismatch refuses, keeps nothing, and leaves no file
  for Helium. A `.crx` signed for another ID refuses too.
- **Install and re-install.** The file names the `.crx` path and version and
  has no other keys. A re-install downloads nothing and leaves the file as it
  was.
- **Update.**
  - It refuses a release with no digest or a wrong one.
  - A dry update downloads nothing.
  - An update moves the file to the new version and removes the old directory.
  - The pinned install never downgrades.
- **Status.** It reports handed over, in Helium, and removed in Helium.
- **The shell layer, dry run.** With Chaotic-AUR enabled, Helium is
  `chaotic-aur/helium-browser-bin`, never built with paru. It comes before
  Cairn's download and file.
- **Offline.** A failed download leaves nothing behind.

`tests/test-shell.sh`: the layer plans Helium and Cairn. Its status is
degraded without Cairn. The fixture `shell-quickshell-installed` gains
`helium-browser-bin`.

## Live apply on io

io already has `helium-browser-bin` 0.18.3.1-1 (`pacman -Q`). After the tree is
installed, run as the user, not root:

```sh
haseen setup cairn && haseen setup cairn status
```

Then quit Helium and start it again. Chromium reads external extensions only
at start. Open chrome://extensions and check that Cairn appears. `haseen layer
apply shell` does the same as part of the layer.
