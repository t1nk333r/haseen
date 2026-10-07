# haseen vs the reference shells: what's missing

Read-only investigation, 2026-10-07, against `main` at 3bd4c1e (plans 001–072). The 8 gaps the owner approved (§2 items 1–8) are plans 075–082.

References, as read:
- **Omarchy 4**: `/usr/share/omarchy/shell` (plugins/, bar/README.md, plugins/README.md), `/usr/share/omarchy/bin/omarchy-*`, `/usr/share/omarchy/default`.
- **DMS**: https://github.com/AvengeMedia/DankMaterialShell (README; `quickshell/Modules/` listing; `Modules/DankBar/Widgets/`; `Modules/Settings/`; `quickshell/README.md`; `quickshell/translations/`).
- **end-4 ii** (GPL, feature names only): https://github.com/end-4/dots-hyprland, `dots/.config/quickshell/ii/modules/ii/` {background, bar, cheatsheet, dock, lock, mediaControls, notificationPopup, onScreenDisplay, onScreenKeyboard, overlay, overview, polkit, regionSelector, screenCorners, screenTranslator, sessionScreen, sidebarLeft (aiChat, translator, anime), sidebarRight (bluetoothDevices, calendar, nightLight, notifications, pomodoro, quickToggles, todo, volumeMixer, wifiNetworks), verticalBar, wallpaperSelector}, `ii/services/` (Brightness, HyprlandXkb, Updates, Todo, TimerService, Translation, SongRec, AntiFlashbang…), `ii/translations/`, `ii/modules/settings/`.
- **caelestia** (GPL, feature names only): https://github.com/caelestia-dots/shell (README with the full config reference; `modules/` {bar, dashboard, drawers, launcher, lock, nexus (settings), notifications, osd, session, sidebar, utilities (toasts, quickToggles, recordings), areapicker, background (desktopClock, visualiser), windowinfo, BatteryMonitor, IdleMonitors}).
- **noctalia**: https://github.com/noctalia-dev/noctalia (MIT). Note: v5 is native C++/Wayland, not Quickshell. Sources: README; `docs/user/bar/widgets/*`, `docs/user/launcher/index.mdx`, `docs/user/configuration/shell.mdx` (accessibility, OSD kinds, `lang` + RTL, hot corners, session), `docs/user/services/*`.

Legend: **H** has · **P** partial · **M** missing · **R** rejected by haseen · – not found in the reference.

## 1. Feature matrix

### Bar widgets
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Workspaces | H `haseen.workspaces` | H | H WorkspaceSwitcher | H Workspaces.qml | H | H |
| Clock (+ calendar) | H `haseen.clock` → `haseen.calendar` | H (month grid, timezone selector) | H | H ClockWidgetPopup | H | H |
| Tray | H `haseen.tray` (hover drawer, native menus) | H | H | H SysTray | H | H |
| Audio / BT / network / battery | H | H | H | H | H | H |
| Media | P label + play/pause/scroll only (`haseen.media/Widget.qml`) | H cover-art popup | H Media + MediaLyricLine | H Media + mediaControls | H dashboard media/lyrics | H media.mdx |
| System usage | H CPU/mem/GPU (`haseen.sysusage`) | – (omarchy-system-stats via power panel) | H CPU/RAM/temps/disk/net | H Resources(+popup) | H dashboard performance | H sysmon |
| Keyboard layout | **M** | H KeyboardLayout.qml | H KeyboardLayoutName | H HyprlandXkbIndicator | H statusIcons kbLayout | H keyboard-layout |
| Active window title | **M** (owner uses compat t1nk33r.window-title) | H ActiveWindow | H FocusedApp | H ActiveWindow.qml | H activeWindow | H active-window |
| Microphone | P (privacy dot + audio panel input) | H Microphone.qml | – | – | H statusIcons microphone | H (volume input) |
| Updates available | **M** (CLI `haseen update` only) | H SystemUpdate | H SystemUpdate | H services/Updates.qml | – (CLI) | – |
| Weather | H (off by default) | H | H | H bar/weather | H dashboard | H |
| Privacy (mic/cam/screen/location) | H `haseen.privacy` | – | H PrivacyIndicator | H services/Privacy | – | H privacy |
| Power profile | **M** (CLI `haseen powerprofile *`) | H power panel | H | – | H (power-profiles-daemon dep) | H power-profile |
| Brightness | **M** | H omarchy.monitor | H DisplayService | H QuickSliders | H scroll action | H brightness |
| Caps/Num lock | **M** | – | H CapsLockIndicator | – | H toasts | H lock-keys |
| VPN | **M** | H tailscale panel | H Vpn | – | H vpn toggle | – |
| State indicators (DND, night light, recording, stay awake, context) | H `haseen.indicators`, `haseen.idle`, `haseen.pager` | H indicators/ | H IdleInhibitor | H UtilButtons | H | H caffeine/nightlight |
| Script-backed custom widget | **M** (QML plugin only) | H `type: command` (bar/README) | – (plugins) | – | – | H custom-button/text |
| Taskbar / running apps | M (fits the no-dock rule) | – | H RunningApps/AppsDock | H TaskbarApps | – | H taskbar |
| haseen-only | prayers, gestures, logo, agents | | | | | |

### Panels and popouts
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Control center / quick settings | P separate panels + indicators toggles + menu Trigger › Toggle | – (per-widget popups) | H ControlCenter | H sidebarRight quickToggles | H utilities quickToggles | H control-center |
| Calendar | H month, weeks, moon, Hijri via prayers | H | H Calendar (event sync) | H | H | H (+ calendar service) |
| Media panel | **M** | H | H DankDash | H | H | H |
| Notification center | H pager Recent + disk history | H | H | H | H sidebar | H |
| Wi-Fi | H (speed test, band, DNS, QR) | H | H | H | H | H |
| Bluetooth (device battery) | H | H | H | H | H | H |
| Audio (per-app, devices) | H | H | H | H volumeMixer | H | H |
| Power profiles / battery details | **M** native (Omarchy compat plugin in use) | H power panel | H | H BatteryPopup | H | H |
| Display / brightness panel | **M** | H monitor panel | H DisplayConfigTab | H QuickSliders | H | H |
| Tailscale / VPN panel | M | H | H NetworkVpnTab | – | H | – |

### Launcher
| Ability | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Apps (fuzzy) | H `haseen.launcher` + menu Apps | H menu | H Spotlight | H overview search | H | H |
| Calculator | H `=` (`Calc.js`, no units) | – | H | H (math) | H qalc | H libqalculate + units/currency |
| Emoji | P separate panel `haseen.emoji` | H overlay | H | H | – | H `/emo` |
| Clipboard | H `>` + panel with image preview | H overlay | H | H | – | H |
| Files | **M** | – | H dsearch | – | – | – |
| Web search | **M** | – | – | H | – | – |
| Commands / actions | P (menu has search; not in launcher) | H menu | H commands | H | H `>` actions | H dmenu providers, `/session`, `/pan` |
| Window switcher | **M** (ALT+TAB = Hyprland cycle, `binds.lua:172`) | – | H running windows | H overview | – | H `/win` |
| Wallpaper picker in launcher | P separate panels | – | – | – | H `>wallpaper` | H `/wall` |
| dmenu / script picker | P plan 071 `haseen menu select` (branch) | H omarchy-menu-select | – | – | – | H `noctalia dmenu` |

### On-screen displays
| OSD | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Volume | H | H | H | H | H | H |
| Brightness | H (actual_brightness watch) | H | H | H | H | H |
| Mic | **M** | – | H OSDTab | – | H enableMicrophone | H volume_input |
| Caps lock | **M** | – | H | – | H toast | H lock_keys |
| Keyboard layout | **M** | – | – | – | H toast | H keyboard_layout |
| Power profile / DND / night light toggles | P (notification on screensaver toggle only) | – | – | – | H toasts | H |
| Keyboard backlight | M | – (omarchy-brightness-keyboard) | – | – | – | H |

### Lock screen and greeter
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Lock (PAM) | H `haseen.lock` | H | H | H | H | H |
| Fingerprint | H | H | H | – | H fprint + howdy | – |
| Media / notifications / session controls on lock | **M** (clock + password only) | – | H LockWidgetSettings | – | H hideNotifs, enableSessionControls | H |
| Greeter | H `haseen-greeter` + tuigreet (arch §9) | – (sddm) | H Greetd + dank-greeter | – | – | H separate project |
| Boot splash | H Plymouth | H | – | – | – | – |

### Wallpaper and theming
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Theme picker | H `haseen.themepicker`, 23 themes | H | H ThemeBrowser | H | H scheme | H |
| Wallpaper picker | H `haseen.background`, `haseen.imagepicker` | H image-picker | H | H wallpaperSelector | H | H |
| Colours from wallpaper | H on demand: `haseen theme wallpaper`, `haseen theme generate` (matugen, 067), Wallhaven (072) | – | H automatic matugen | H automatic | H dynamic scheme | H |
| Slideshow / automation | **M** (`theme bg next` by hand) | – | H WallpaperCyclingTab | – | H random | H automation |
| Light/dark schedule | M | – | H ThemeScheduleTab | – | H setMode | H theme-mode |
| App templates | H themed/*.tpl, nvim | H | H | H | H | H |
| Per-monitor wallpaper | M (swaybg same image on all outputs) | – | H | – | – | H per-monitor dirs |

### Notifications
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| History | H pager disk history | H | H | H | H | H |
| DND | H `dnd` flag | H | H | H | H | H |
| Grouping | H per source | H | H | H | H groupPreviewNum | H |
| Actions | H | H | H | H | H | H |
| Inline reply | P KDE Connect only (`haseen.pager/Service.qml:1803-1913`) | – | n/c | n/c | n/c | n/c |
| Per-app rules | P per-source snooze/mute | – | H NotificationRulesTab | – | – | – |

### Session, overview, dock, desktop, AI
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| Session/power menu | H `haseen.session` (+ BootNext to Windows) + menu System | H | H PowerMenu | H sessionScreen | H session | H (countdown) |
| Workspace/window overview | **M** | – | H Overview/WorkspaceOverlays | H overview (live previews) | – | – (window-switcher hot-corner action) |
| Alt-tab | P Hyprland cycle | – | H | H | – | H |
| Dock | **R** (arch §1 req 3) | – | H Dock | H dock | – | H dock |
| Desktop widgets | **R** natively (req 3); DMS desktop plugins via compat (plan 054) | – | H DesktopWidgetLayer | H overlay widgets | H desktopClock | H |
| AI chat | H `haseen.ai` (local, loopback) | – | – | H aiChat (Gemini, Ollama) | – | – |
| Translator | **M** | – | – | H translator, screenTranslator | – | – |
| Agent monitor | H `haseen.agents` (running agents) | H agents (usage/limits) | – | – | – | – |

### System and utilities
| Feature | haseen | Omarchy 4 | DMS | end-4 | caelestia | noctalia |
|---|---|---|---|---|---|---|
| System monitor depth | P (no temps/disk/net in panel; sidecar has them, `Sidecar.qml:48-49`); no kill | – | H ProcessList with management | H resources | H storage/network | H system-monitor |
| Screenshot (region/window/output, annotate) | H `haseen capture screenshot` (slurp, satty/swappy) | H | H | H regionSelector | H areapicker | H screenshot widget |
| Recording | H gpu-screen-recorder, webcam | H | – | H overlay recorder | H recordings | – |
| Colour picker | H CLI `haseen capture color` | – | H ColorPicker module | – | – | – |
| OCR / reverse-image search | H Arabic+English OCR, `haseen search-screen` | H capture-text | – | H Google Lens | – | – |
| QR | H | H | – | – | – | – |
| Idle/caffeine | H screensaver/lock/dpms, Stay Awake | H | H separate AC/battery | H | H timeouts incl. suspendThenHibernate | H idle.mdx |
| Idle suspend | **M** | – | H | – | H | H |
| Low-battery warning | **M** | H omarchy-battery-low, notification-battery | H | H Battery service | H BatteryMonitor warnLevels | H |
| Night light | H hyprsunset + fixed HH:MM | H | H GammaControlTab | H nightLight | – | H night-light + location |
| Night light from location | **M** | – | H | – | – | H |
| Gamma control | P (night light only) | – | H | – | – | – |
| Multi-monitor | P bar on every screen; no exclude list or per-monitor config | H | H | H | H per-monitor shell.json, excludedScreens | H `monitors` keys |
| Display arrangement GUI | M (edit monitors.lua) | P monitor-scaling cmd | H DisplayConfig | – | – | – (compositor's job) |
| Accessibility | P contrast floors (064), `Theme.subtle` ≥3:1 (068), fontSize token | – | – | H onScreenKeyboard | – | H ui_scale, high_contrast, readline |
| Settings GUI | **R** (plan 045); CLI `haseen settings` + menu | P | H ~90 tabs | H settings.qml | H nexus | H |
| Plugin system | H registry, lockfile, `requires` gates, safe mode, Omarchy + DMS compat | H | H registry + lockfile | – | – | H |
| Plugin settings UI | M (no writer screen; CLI `haseen plugin settings`; plans 025, 052) | H schema | H Settings.qml | – | – | H |
| i18n | **M** (English; prayers bilingual) | – | H translations/ | H translations/ | – | H `lang` + RTL mirroring |
| Polkit agent | H | H | H | H | – | – |
| Keybind cheatsheet | H `haseen.keybinds` (+ 071 search) | H | H KeybindsTab (editor) | H cheatsheet | – | – |
| Updates | P `haseen update system|firmware`, no indicator | H | H SoftwareUpdatesTab | H Updates | H CLI | – |
| Weather | H (wttr.in + Open-Meteo, GeoClue) | H | H | H | H | H |
| Calendar events | **M** | – | H dankcalendar | – | – | H calendar service |
| Todo / pomodoro / notes | M (reminders only) | H reminders | H Notepad | H todo, pomodoro, notes | – | – |
| Dictation | M (Speech Note in catalogue) | H voxtype + indicator | – | H SongRec (song recognition) | – | – |
| Hot corners | M | – | – | H screenCorners | – | H hot_corners |
| On-screen keyboard | P (DMS OSK via ydotool shim, plan 054) | – | – | H | – | – |
| haseen-only | Secure Boot, contexts, crash recovery/safe mode, gestures, prayers, screensaver, border wipe, VAPT, dual-boot BootNext | | | | | |

## 2. Real gaps, ranked

Ranked by user value and fit with haseen's rules (events not polling, lazy panels, off by default, no clutter). Sizes: S ≤ 1 plan-day, M a few, L a round.

1. **Low-battery warnings.** Notify at warn/critical levels, optionally act at critical. Refs: Omarchy (`omarchy-battery-low`, `omarchy-notification-battery`), caelestia (`BatteryMonitor.qml`, `general.battery.warnLevels`), DMS (BatteryService alerts), end-4 (`services/Battery.qml`), noctalia (`services/battery.mdx`). Approach: add a `service` kind to `haseen.battery` (UPower signals, one notification per threshold crossing; critical action off). Listing it in `services` needs owner approval. Fix the misleading comment at `Compat/Dms/Services/BatteryService.qml:14`. **S**
2. **Brightness.** A `haseen brightness` command (backlight, DDC via ddcutil when present, keyboard backlight) and a display panel with sliders. Refs: Omarchy (`panels/monitor`, `omarchy-brightness-display{,-ddc,-apple}`, `-keyboard`), DMS (DisplayService, `dms brightness list`), end-4 (`services/Brightness.qml`, QuickSliders), caelestia (ddcutil + brightnessctl deps), noctalia (`bar/widgets/brightness`, `services/brightness.mdx`). Plan 057:97 notes it. Approach: command in core; built-in panel `haseen.display`, off by default. The OSD already watches backlight changes. **S + M**
3. **Media panel.** Cover art, title/artist, seek, prev/play/next, player switcher. Refs: all five (Omarchy media popup, DMS DankDash/MediaLyricLine, end-4 mediaControls, caelestia dashboard, noctalia media). Approach: add a `panel` kind to the default `haseen.media`, opened by right/middle click so left-click play/pause stays. Position updates must not tick faster than 2 s (§6). **S–M**
4. **Power profile + battery panel.** Profiles, charge limit, rate/time remaining. Refs: Omarchy `panels/power`, DMS BatteryService/PowerSleepTab, end-4 BatteryPopup, noctalia power-profile, caelestia. Approach: add a `panel` kind to `haseen.battery`, using UPower PowerProfiles signals and the existing `haseen battery status|limit` and `haseen powerprofile *`. This replaces the owner's compat t1nk33r.power. **S–M**
5. **More OSD kinds: mic mute/volume, keyboard layout, Caps Lock.** Refs: noctalia (`[osd.kinds]` volume_input, lock_keys, keyboard_layout), caelestia (`osd.enableMicrophone`, toasts capsLock/kbLayout), DMS (CapsLockIndicator, OSDTab). Approach: extend `haseen.osd`. Mic uses `Pipewire.defaultAudioSource` signals. Layout uses Hyprland's `activelayout` event. Caps Lock: a Hyprland bind calls an IPC verb that reads the LED once, never a poll. Each kind behind a setting, Caps Lock off by default. **S–M**
6. **Keyboard-layout bar widget.** Zero width with one layout, so it can sit in `bar.right` like `haseen.gestures`; relevant to Arabic/English. Refs: Omarchy KeyboardLayout, DMS KeyboardLayoutName, end-4 HyprlandXkbIndicator, caelestia kbLayout, noctalia keyboard-layout. Approach: built-in off (or zero-size default, with owner approval); Hyprland events only; click runs `switchxkblayout`. **S**
7. **Launcher providers: window switcher, emoji, menu commands, web search.** Refs: DMS Spotlight (windows, emoji, commands, files), noctalia (`/win`, `/emo`, `/session`, `/pan`, dmenu), end-4 (web search, math, commands), caelestia (`>` actions). Approach: one built-in `launcher-provider` plugin each, off by default. Providers already exist only while the launcher is open. Window switcher = `Hyprland.toplevels` → focus. Emoji reuses `haseen.emoji/emojis.json`. Commands reuse `MenuModel.js`. Web search = `xdg-open` with a URL template (no network from the shell). Files would need an index (dsearch/plocate), so it is a later step. **S each**
8. **Idle suspend and AC/battery timings.** Refs: caelestia (`general.idle.timeouts` suspendThenHibernate), DMS ("auto-lock/suspend with separate AC/battery settings", README), noctalia (`services/idle.mdx`). Approach: `haseen.idle` gains `suspendAfter` (0 = never) and optional `onBattery` overrides driven by UPower `onBattery`. Core change, default unchanged. **S**
9. **Night light from location.** Refs: noctalia (night-light + location services), DMS GammaControlTab. Approach: `haseen.nightlight` `schedule: "sun"` reuses the prayers engine's offline sun times (+ GeoClue/settings location). The existing 60 s check (plan 019) stays. **S**
10. **Deeper system monitor.** Temperatures, disks, network rates; kill a process. Refs: DMS (CpuTemperature, GpuTemperature, DiskUsage, NetworkMonitor, ProcessList), caelestia dashboard performance, noctalia sysmon, end-4 resources. Approach: core change to the `haseen.sysusage` panel. The sidecar already provides `cpuTempC`, net and disks (`Sidecar.qml:48-49`). Kill only after a confirm. **S**
11. **Update-available indicator.** Refs: Omarchy SystemUpdate (`omarchy-update-available`), DMS SystemUpdate/SoftwareUpdatesTab, end-4 `services/Updates.qml`. Approach: a systemd user timer (e.g. hourly) runs `checkupdates` + `flatpak remote-ls --updates` into a state file. A built-in `haseen.updates` widget (off) watches the file; click runs `haseen update`. Replaces compat t1nk33r.updates. **S–M**
12. **Lock screen extras.** Caps-lock warning, battery, keyboard layout, media controls, unread count, optional session buttons. Refs: caelestia lock (hideNotifs, enableSessionControls), DMS LockScreenTab/LockWidgetSettings, noctalia lockscreen. Approach: core change to `haseen.lock` `LockView.qml`, each item a setting; Caps-lock warning on by default. **S–M**
13. **Workspace/window overview.** Grid of workspaces with window icons and titles; click or keys to focus and move. Refs: end-4 overview, DMS Overview/WorkspaceOverlays, noctalia window-switcher action. Approach: built-in overlay `haseen.overview`, off by default, no screen capture by default (memory). Not rejected anywhere; on demand. **M (L with live previews)**
14. **Quick-settings card.** One on-demand card: Wi-Fi/BT/DND/night light/stay awake/context toggles plus volume/brightness/mic sliders and power profile. Refs: DMS ControlCenter, noctalia control-center, end-4 quickToggles/QuickSliders, caelestia quickToggles. Approach: built-in panel `haseen.quick`, off, opened by a bind. It only calls existing commands and flags. Overlaps menu Trigger › Toggle and the indicators widget, so it ranks below the items above. **M**
15. **Wallpaper rotation.** Refs: DMS WallpaperCyclingTab, noctalia automation, caelestia `wallpaper -r`. Approach: `haseen setup bg-cycle <interval|off>` installs a systemd user timer running `haseen theme bg next` (or `wallhaven random`). Never regenerates colours automatically (§6). **S**
16. **Script-backed bar widget.** Refs: Omarchy bar/README "Custom user modules" (`type: command`, interval, Waybar JSON), noctalia custom-button/text. Approach: built-in `haseen.command`, off. Minimum interval 2 s with a `// haseen:sample` gate, or `watch` a file instead of an interval. Supports requirement 2 (extendable). **S**
17. **Choose which monitors get a bar.** Refs: caelestia `bar.excludedScreens` + per-monitor config, noctalia `monitors`, DMS per-monitor. Approach: `bar.screens` allowlist in `shell.json`, read by the `Variants` model in `shell.qml`. Per-output wallpaper is a separate M. **S**
18. **Active-window title widget.** Refs: Omarchy ActiveWindow, DMS FocusedApp, end-4 ActiveWindow, caelestia activeWindow, noctalia active-window. Approach: built-in, off; Hyprland events. Replaces compat t1nk33r.window-title. **S**
19. **VPN status/toggle in the network panel.** Refs: DMS Vpn/NetworkVpnTab, caelestia `utilities.vpn`, Omarchy tailscale panel. Approach: core change to `haseen.network` panel (NetworkManager VPN/WireGuard connections). **S**
20. **Inline reply for any app.** The pager answers only KDE Connect forwards. [INFERENCE] Quickshell's NotificationServer exposes inline-reply support; I did not confirm which reference shells use it. Approach: core change to `haseen.pager`. **S**
21. **Local-AI translate** (text or an OCR'd region). Refs: end-4 translator + screenTranslator. Approach: `haseen ai translate` over the existing `haseen ai chat` + `haseen capture text`; a built-in panel mode, off. Fits requirement 6 (local AI). **S–M**
22. **Calendar events** (read-only ICS/CalDAV in `haseen.calendar`). Refs: DMS dankcalendar, noctalia calendar service. Approach: off by default, fetched by a timer of 15 minutes or more into a state file. **M–L**
23. **Todo / pomodoro / notes panel.** Refs: end-4 todo, pomodoro, overlay notes; DMS Notepad. Approach: built-in panel, off. Low value next to the existing reminders. **S–M**
24. **UI scale and high-contrast mode.** Refs: noctalia `[accessibility] ui_scale, high_contrast`. Approach: `shell.json ui.scale` multiplies Theme sizes; high contrast forces the contrast floors to their maximum. **S–M**
25. **i18n + RTL.** Refs: DMS translations (POEditor), end-4 translations, noctalia `lang` + RTL mirroring. Approach: `qsTr` everywhere plus Arabic RTL; zero `qsTr` calls today. **L**
26. **Dictation.** Refs: Omarchy voxtype (`omarchy-voxtype-*`, Dictation indicator). Approach: optional `haseen setup dictation` + an indicator entry (`Indicators.js:11` notes its absence). **M**
27. **Compat gaps.** DMS `launcher` surfaces → haseen launcher-provider (arch §5.4 lists them unsupported); `omarchy-shell` IPC translator (plan 057:89 "should exist"); `haseen launch tui` (057:94, 068:152); `haseen display scale` (057:98). **M each**
28. **Light/dark theme schedule.** Refs: DMS ThemeScheduleTab, caelestia setMode, noctalia theme-mode. Approach: a timer pairing `haseen theme set A|B`. **S, low**
29. **Hot corners.** Refs: noctalia hot_corners, end-4 screenCorners. Approach: built-in, off; invisible strips. **S, low**

Not recommended, though no plan rejects them: taskbar/running apps (works against "no dock"), a QML screenshot region selector (slurp works), colour-picker GUI with history, Booru/anime, song recognition, anti-flashbang shader (shaders are banned by §6).

## 3. Deliberately rejected: do not propose again
| Item | Reference that has it | Where haseen rejected it |
|---|---|---|
| Dock | DMS, end-4, noctalia | `docs/architecture.md` §1 req 3 ("no dock") |
| Native desktop widgets | DMS, end-4, caelestia, noctalia | §1 req 3 ("no desktop widgets"); DMS desktop plugins only via compat (plan 054) |
| Settings GUI / keybind editor / ~90-tab hub | DMS, end-4, caelestia, noctalia | plan 045 "Rejected: A settings GUI" |
| Blur, shaders, blurred live wallpaper, audio visualiser (cava) | DMS, caelestia, noctalia | §6 (no blur, no shaders; the border wipe is the one continuous animation) |
| Automatic colour generation on wallpaper change | DMS, end-4, caelestia, noctalia | §6; plan 008 (matugen not installed for runtime). On-demand generation is plan 067 |
| Typing emoji by injecting keys | end-4 (Ydotool), Omarchy `omarchy-menu-emoji-insert` | plan 018 (wtype rejected) |
| One full-screen drawer/frame window | caelestia drawers | plan 015 |
| Menu button as a separate widget | Omarchy | plan 016 (later the `haseen.logo` mark opens the menu, plan 070) |
| walker / elephant / fastfetch | Omarchy | plan 038 |
| qt6ct / Kvantum | end-4 (Kvantum) | plan 047 |
| Aether | Omarchy | plan 067 (owner dropped) |
| Stacking contexts | – | plan 062 |
| Dragging the bar to move it | Omarchy | plan 051 |
| Remote images in notification bodies | DMS (rich text) | plan 010 (tracking pixels) |
| Moving personal built-ins to opt-in | – | plan 054 (owner kept them) |
| System-scope Flatpak, GeForce NOW installer, factory reset, direct boot, update channels | Omarchy | plans 017, 068 |
| SUPER+ALT+B blackout bind | – | plan 043 |
| xdg-popup panels | – | plan 049 |
| NixOS | DMS, caelestia, noctalia | plan 009 (dropped) |

Note: plan 005 rejected custom QML tray menus, but the installed `haseen.tray` now ships `TrayMenu.qml`, so a later round reversed that.

## 4. Checks the main agent should run
None; this was investigation only. To confirm the top gap: `rg -n 'percentage|notify' share/haseen/shell/plugins/haseen.battery` shows no notification path.