# Plan 040: Phones — the Android half that works, the iOS half that exists

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (opt-in layer; one named firewall hole)
- **Depends on**: 001 003
- **Category**: system
- **Planned at**: 2026-10-05, owner request (item 10: "android/ios support")
- **State**: DONE 2026-10-05

## Problem

haseen had no story for phones. Android and iOS need completely different
stacks; the useful half of each is easy to name and the useless half is heavily
marketed. Two concrete traps:

- the base layer's ufw `DEFAULT_INPUT_POLICY=DROP` silently breaks the one
  Android feature people actually want (KDE Connect);
- iOS parity is routinely promised and cannot be delivered — Apple exposes no
  third-party API for notifications, SMS or media control.

## Decision

One **opt-in `mobile` layer** (`LAYER_REQUIRES="desktop"`), ten official-repo
packages, **no AUR**, **no services enabled**, one firewall hole that is named
and justified, and three commands.

- **Android**: `android-tools 37.0.0-5`, `android-udev 20260423-1`,
  `scrcpy 4.1-2`, `kdeconnect 26.08.0-1` (standalone `kdeconnectd`, no Plasma),
  `gvfs-mtp 1.60.2-4`, `android-file-transfer 4.5-2` (`aft-mtp-mount`).
- **iOS**: `usbmuxd 1.1.1-4`, `libimobiledevice 1.4.0-2` (which ships
  `idevicebackup2`), `gvfs-afc 1.60.2-4`, `gvfs-gphoto2 1.60.2-4`.
- **Firewall**: KDE Connect needs TCP+UDP `1714:1764` inbound. The layer adds
  exactly those two ufw rules through `run_root`, idempotently, or firewalld's
  own `kdeconnect` service in the home zone when firewalld is what is enabled,
  or it **warns** when there is no firewall rather than pretending. `layer_remove`
  deletes the rules and leaves packages and pairings alone.
- **Nothing is `systemctl enable`d**: `kdeconnectd` is XDG-autostarted and D-Bus
  activated, `usbmuxd` starts from its udev rule. An enable line would be a
  second source of truth that drifts.
- **Two claims are probed, not asserted.** The ifuse gate reads the version the
  repos offer, and the KDE Connect Mousepad verdict reads the installed
  `.portal` files.
- **The limits are printed where the user is**, in the layer summary and in
  every command's `--help`, not filed in a plan nobody reads: iPhone
  notification mirroring, SMS and media control are not possible; KDE Connect's
  Mousepad plugin is broken on Hyprland because no installed portal backend
  implements `RemoteDesktop` (`/usr/share/xdg-desktop-portal/portals/hyprland.portal`
  lists Screenshot, ScreenCast, GlobalShortcuts, InputCapture — no RemoteDesktop);
  Android has no maintained backup tool, so `haseen mobile backup` is iOS-only.
- **Commands**:
  - `haseen mobile status` is a report, not a health check. It classifies
    `/sys/bus/usb/devices` through `sysroot_path`, then asks `adb devices`,
    `kdeconnect-cli`, `idevice_id -l` and `idevicepair validate`. An Apple
    device (05ac) counts as iOS only with the usbmux interface (class ff,
    subclass fe, protocol 02) or a product id in the range usbmuxd's udev rule
    matches, 129x-12ax (`/usr/lib/udev/rules.d/39-usbmuxd.rules`, usbmuxd
    1.1.1-4); the range covers a device whose configuration that rule set to
    0, which takes its interfaces out of sysfs. An Apple keyboard is not a
    phone.
  - `haseen mobile mirror` runs scrcpy and refuses *before* scrcpy's wall of
    adb text. `--v4l2` checks for `v4l2loopback-dkms` rather than assuming it
    and writes only into the node haseen made (`card_label=haseen-phone`):
    with none it loads the module (`run_root modprobe v4l2loopback
    exclusive_caps=1 card_label=haseen-phone`, then `udevadm settle` and a
    character-device check); with the module already loaded by another
    program (OBS's virtual camera) it refuses, because a second modprobe adds
    no node, and names `--v4l2=/dev/videoN` for using that camera on purpose.
    Nodes are listed in numeric order (video2 before video10).
  - `haseen mobile backup` runs `idevicebackup2 backup --full` into a DIR it
    creates mode 0700, under umask 077 (upstream makes its directories 0755
    and opens files with the default mode). An existing DIR that is not the
    user's, or is open to group or others, is refused (dry run included) with
    the `chmod 700` fix; its mode is never changed for the user. Encryption is
    the phone's `WillEncrypt` setting: the command reads it with `ideviceinfo`
    and reports on, OFF (with the `idevicebackup2 -u UDID encryption on`
    hint) or unknown before asking, and never changes it.
- **firewalld**: the `kdeconnect` service goes to the home zone only. When
  `DefaultZone` (world-readable `/etc/firewalld/firewalld.conf`, default
  `public`) is not `home`, apply warns that pairing works only on a network in
  the home zone and how to move a connection there.

## Rejected

| option | why | evidence |
|---|---|---|
| `ifuse` | `extra/ifuse` is **1.2.0-1**, the exact version upstream says corrupts data (fixed in 1.2.1). `gvfs-gphoto2` + `gvfs-afc` cover what AFC permits anyway. | `pacman -Si ifuse` 2026-10-05; upstream README |
| GSConnect | a GNOME Shell extension — cannot load under Hyprland at all | `metadata.json.in` `shell-version [46..51]`; AUR only |
| Valent | alpha, zero releases ever, last commit 2026-03-15, nightly flatpakref only | `/releases/latest` 404; `flatpak remote-info flathub ca.andyholmes.Valent` → no ref |
| jmtpfs | upstream dead since 2013-11-26, AUR-only; `aft-mtp-mount` supersedes it | last commit `928fb8f` |
| warpinator | redundant with LocalSend and has no iOS client | LocalSend ships official iOS and Android clients |
| opendrop / owl (AirDrop) | last release 2021-04-29; mandates `owl`, which has no package anywhere and needs a patched monitor-mode Wi-Fi driver | `aur/owl-wifi`, `aur/owl-git` → none |
| ancs4linux (iPhone notifications) | the only ANCS implementation: zero releases, no package anywhere, author's README says he stopped using it | empty `releases.atom` |
| waydroid **in this layer** | a full LXC container with a kernel precondition this machine does not meet, plus an open Hyprland logout bug | `/proc/config.gz`: `CONFIG_ANDROID_BINDER_IPC` and `_RUST` not set; no `/dev/binder`; waydroid issue #2427 |
| `systemctl enable kdeconnectd/usbmuxd` | both already start themselves | package file lists |
| a `90-mobile.sh` seed | nothing to seed: KDE Connect writes its own config on first run | package ships no default to include |
| any Apple vendor id (05ac) as iOS | an Apple keyboard or trackpad is listed as a phone | `tests/fixtures/mobile-applied` 05ac:024f (HID) |
| the lowest loopback node when haseen's is missing | with only OBS's virtual camera loaded, scrcpy wrote into it; a second `modprobe` of a loaded module adds no node | `tests/test-mobile.sh` OBS cases |
| narrowing the ufw rule to one subnet | haseen cannot know the user's subnet and a wrong guess silently breaks pairing; the layer prints the ports it opened so the user can narrow them | KDE UserBase firewall section |

## Verification

- `tests/test-mobile.sh` over two fixtures (`mobile-plain`, `mobile-applied`):
  package set and order, the ufw rules and their idempotency, the firewalld
  branch and its zone warning, the no-firewall branch, `--no-firewall`,
  `--v4l2`, unknown flags, the ifuse refusal in three states (1.2.0 / unknown
  / fixed 1.2.1), status at four health levels, `layer_remove`, and every
  command's `--help` and its behaviour with no device, an unauthorised device
  and two devices. Dry-run purity is asserted on every mutating path.
- The USB classifier: an iPhone in the usbmux range, Android in ADB and MTP
  mode, a root hub and an Apple keyboard (05ac:024f, HID) that must not
  match, and an Apple device outside the range that becomes iOS only once it
  shows the usbmux interface.
- `mirror --v4l2`: haseen's node among three loopback nodes, haseen's node
  over a lower OBS node, OBS's nodes alone with the module loaded (refused, no
  modprobe, no sink), the same nodes without the module (modprobe planned,
  next index predicted), and an explicit `--v4l2=DEV`. The fixtures' empty
  sysfs `device` directories, which tell a real camera from a loopback node,
  hold a `.keep` so git keeps them.
- Live on the reference machine (2026-10-05): `haseen mobile status` exits 0
  with no phone attached; `haseen layer status mobile` reports this host as
  half-installed with the ports closed; `haseen layer apply mobile --dry-run`
  plans exactly the four missing packages and the two ufw rules.

## Open

No phone was attached, so pairing, mirroring and an iOS backup were exercised
against fixtures and refusal paths only.

## Execution record

`share/haseen/layers/mobile/{layer.sh,mobile.sh,packages.txt}`,
`bin/haseen-mobile-{status,mirror,backup}`, `tests/test-mobile.sh`,
`tests/fixtures/mobile-{plain,applied}/`. `tests/test-install-picker.sh`
numbers `mobile` 11 among the sorted optional layers.
