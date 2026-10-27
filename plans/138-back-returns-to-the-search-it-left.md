# Plan 138: Back returns to the search results it left, on the row it left

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. The nav frame gains the query as text; every forward step
  still starts with no query, and a page entered from outside (a route, a
  panel) still has none.
- **Depends on**: 068 (the menu port and its Back), 132 (agent accounts, the
  rows the owner was searching)
- **Category**: shell
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27 (`tests/test-menu-back.sh` 34/34)

## Problem

Owner, 2026-10-27:

> on the lancher meun when accessing a submenu and comming out of it i lose the
> preivoues index i was on like / i search for agent accounts and i access it
> when i come back from it by left arrow i get sent to the first page and not
> the search items i was on

`haseen.menu`'s `enter()` cleared `filterText` on **every** step
(`filterText = ""`), and each nav frame kept only `{ menu, row }`. So Back restored the parent menu and tried `selectRow(row)` on
it — but with the query gone, the row it was told to select was not in the
model at all (a search result, often a *deeper* row, is not a child of the
page). `selectRow` silently no-ops, `selectedIndex` is 0, and the card is the
unfiltered page: "the first page".

Plan 068 accepted that: its test asserted `.query == ""` after Back and a
selection of `Apps >`. The owner has now used it, and it is wrong — the search
is the context the user was in, and Back should return to it.

## What changed

- The nav frame carries the query it was left in:
  `navStack.concat([{ menu: activeMenu, row: rowId, filter: filterText }])`.
- `enter()` takes an optional `restore`: a forward step passes nothing and gets
  `""` as before; `goBack()` passes `frame.filter`, so the parent page is
  rebuilt **with** the query, and the row it selects exists again.
- A restored query re-asks the providers (`searchProviders()`), as
  `setFilter()` does, so provider rows that arrive late are there too; then
  `selectRow(frame.row)` lands on the row that opened the submenu and
  `revealCursor` scrolls it into view.
- Only text is restored: the cursor row comes back by `itemId` through the
  existing `selectRow`, so a page whose order changed still selects the same
  row.

Rejected: keeping the query only when it is non-empty (same thing, more
branches); restoring the scroll offset instead of the row (the row is the
anchor the user had); a "search mode" flag (the query text already is one).

## Tests

`tests/test-menu-back.sh` — search `reminder`, open the deep `trigger.reminder`
submenu, Back: the query is `reminder` again, the same rows come back in the
same order, and `Reminder >` is selected. Search `link`, enter the *second*
result (`System Link >`), Back: the cursor returns to index 1, not to the top.
Search `about`, open the About view, Back: the query and its row. Against the
old `Panel.qml` the same file fails six assertions (28/34: `Apps >` instead of
`Reminder >`, the unfiltered root rows, cursor on 0, no query); with this,
34/34.

## Evidence

- `share/haseen/shell/plugins/haseen.menu/Panel.qml:250` — the frame keeps
  `filter: filterText`.
- `Panel.qml:254` — `filterText = typeof restore === "string" ? restore : ""`.
- `Panel.qml:278` — `setActiveMenu(frame.menu, false, false, "", frame.filter)`.
- `Panel.qml:541,554-558` — `run(action, rowId)` keeps the About view's origin
  row, so Back from About returns to it too.
