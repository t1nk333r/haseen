# Plan 169: reply from a notification card, for any app

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW–MEDIUM. The pager starts advertising a capability, so
  senders that check it (Telegram, Signal, Thunderbird, some chat web apps)
  send reply-able notifications. The reply field and its flow already exist
  for KDE Connect; this plan gives them a second backend.
- **Depends on**: the pager port, 109 (interface language)
- **Category**: shell
- **Planned at**: 2026-11-14, from the owner (sent lucid's repository, "what
  could be good to take", then "go")
- **State**: PLANNED 2026-11-14

## Problem

The freedesktop notification spec lets a sender ask for an inline reply
(the `inline-reply` action; the server must advertise the
`inline-reply` capability). Quickshell 0.3.2 exposes it:
`NotificationServer.inlineReplySupported`, and on a notification
`hasInlineReply`, `inlineReplyPlaceholder` and `sendInlineReply(text)`
(`/usr/lib/qt6/qml/Quickshell/Services/Notifications/quickshell-service-notifications.qmltypes:165-218,368`).
Lucid turns it on and shows a reply field on the card (`Notifs.qml:341-348,462`,
`lucidnotif/NotifActions.qml:74`).

haseen's pager does not advertise it (`haseen.pager/Service.qml:2120-2131`
lists image, actions, markup, hyperlinks and persistence only), so no app
offers a reply. Yet the pager already has the whole reply UI: a "Reply" deed
(`Toast.qml:125-135`), a reply field with placeholder, error line, send and
cancel (`Toast.qml:794-877`), a `replyingKey` that holds the card open
(`Service.qml:1177,1580`) and `sendReply(key, text)` (`Service.qml:1972-1983`).
Its only backend is KDE Connect: `lookForReply` finds the phone
conversation (`Service.qml:1939-1950`), sets `replyPath`
(`Service.qml:1925`), and `sendReply` runs `kdeconnect.sh reply`.

## Decision

- `NotificationServer { inlineReplySupported: true }`.
- In `handleNotification` (`Service.qml:1402`), a notification with
  `hasInlineReply` gets `replyPath: "inline"` and `replyTo` from its
  `inlineReplyPlaceholder` (falling back to the summary, as now) before
  `lookForReply`; `lookForReply` leaves a row that already has a path alone.
  `Store.js` already carries `replyPath`/`replyTo` and clears both on load
  (`Store.js:85,102,128,229`), so a stored row never offers a dead reply.
- `sendReply`: when `replyPath === "inline"`, it calls
  `refs[key].sendInlineReply(text)` (the live object, as `invokeAction`
  reaches it, `Service.qml:1679-1693`), inside `try`, with the same 4096-char
  bound, then closes the card as an action does. A sender that has gone
  (`refs[key]` missing) shows the existing reply error line ("Could not
  send"). Everything else stays KDE Connect's path.
- The deed filter that hides the phone's own "Reply" action
  (`Toast.qml:132-134`) applies to an inline-reply row too, since the spec
  sends `inline-reply` as an action identifier.
- No new strings beyond what the field already has; any new one goes into
  `share/haseen/i18n/ar/shell.json`.

The reason for a new on-screen element (CLAUDE.md, "No visual clutter"):
none; a Reply deed appears only on a card whose sender asked for one.

## Rejected

- **Grouping cards by app**: the pager already stacks and groups per source
  (`manifest.json:6`, `Service.qml:44`, `stacking: "source"`).
- **Reply in haseen.notifications**: it is the fallback daemon, not running
  by default (`share/haseen/default/shell.json:44`), and its popup window
  takes no keyboard focus (`haseen.notifications/Service.qml:198`).
- **A setting to turn it off**: the deed does nothing until clicked, and
  only for senders that asked; a setting adds a switch nobody needs. If an
  app misbehaves, the plan can add one then.

## Evidence (to collect)

- `tests/test-pager.sh`: the server declares `inlineReplySupported: true`;
  a fake notification with `hasInlineReply` gets `replyPath === "inline"`;
  `sendReply` calls `sendInlineReply` and never `kdeconnect.sh` for it; the
  KDE Connect path still runs for a KDE Connect row.
- By hand: `gdbus call` a notification with an `inline-reply` action and
  watch `NotificationReplied` with `dbus-monitor` after typing in the card.
