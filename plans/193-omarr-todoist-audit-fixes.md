# Plan 193: omARR and Todoist fixes from the 2026-11-24 audit

## Status

- **Priority**: P1 (the qBittorrent login could get the owner's own address
  banned from the WebUI for an hour)
- **Effort**: S
- **Risk**: LOW. All four changes stay inside `haseen.omarr` and
  `haseen.todoist`, both off by default (plan 097). A refused qBittorrent
  login now stops the polls to that service for an hour unless the URL or
  credentials change. Todoist edits and deletes now wait their turn behind
  closes in one queue.
- **Depends on**: 097 (the plugins), 100 (affected tests)
- **Category**: plugins
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit of 2f7f472a)
- **State**: DONE 2026-11-24 (`tests/test-omarr.sh` 97/97,
  `tests/test-todoist.sh` 69/69; review round 1 addressed, see Review)

Each finding was traced again on main at 9a9e82ab before it was fixed. The
line numbers below are from that commit, which matches the audited
2f7f472a for these files. Each new check was run against 9a9e82ab's
plugins (a detached worktree with this plan's tests copied in): omarr 89/96,
todoist 64/69. Every new engine check failed there and passes here.

## 1. A wrong qBittorrent password shows as healthy and is retried until qBittorrent bans the address

**Evidence.** qBittorrent answers a refused login with HTTP 200 and the body
`Fails.`. `Service.qml:803` set `qbitReady` false for it, but `:808` then
called `commitHealth(service, snap, parsed.status || 401)` with status 200,
so `Model.decideHealth` (`Model.js:1924-1926`) returned up and
`applyHttpHealth` (`Model.js:1902-1908`) wrote "Reachable". Nothing
remembered the refusal: `enqueueQbit` (`Service.qml:1324-1330`) logged in
again on every poll while `ready` was false. With the fields blank,
`torrents/info`'s 403 logged in as `admin` with an empty password, and that
looped too. With the panel open, the 2 s downloader timer (`:1871`) drove
the loop. On 9a9e82ab the new engine check showed the row as
`up|Reachable`, and the wrong password went out 4 times in the 5 s the
probe held the panel open. qBittorrent's stock settings ban an address
after 5 failures, for an hour.

**Fix.** `Model.qbitLoginOutcome(status, body)` decides a login: "ok",
"refused" or "error". Only an answer about the credentials is a refusal: a
2xx/3xx with a `Fails` body, or a 401 or 403 (a ban, or a WebUI that wants
other credentials). Any other answer (a 502 or 503 from a reverse proxy or
VPN container while qBittorrent restarts, a 404, a 429, no status) is an
error: it clears any hold, is committed through `commitHealth` with its
code ("HTTP 503"), and the next poll logs in again, as before this plan.
`Model.qbitLoginOk` is `outcome === "ok"`. A refusal is committed down
through `Model.applyLoginFailure` (health down, status "Login failed", new
string, with Arabic), whatever the HTTP code. The service records
`{key, at}` in `qbitLoginFailed`. The key is an md5 of the URL, user name
and password the login sent (`qbitLoginKey`). While `Model.qbitLoginHeld`
holds (same key, under `QBIT_LOGIN_RETRY_MS`, an hour), `enqueueQbit` sends
nothing to that service. `enqueueQbitLogin`, reached from a 401/403 on
`torrents/info`, recommits "Login failed" instead of logging in. New
credentials or a new URL change the key, so they go out at once. A good
login clears the record, and so does removing the service.

**Test.** `haseen.omarr/tests/Model.test.js`: 200 `Fails.`, 401 and a 403
ban page are refusals; 502, 503 (even with a `Fails.` body), 504, 404, 429
and no status are errors. A refused snapshot is down with "Login failed".
The hold lasts the hour for the same key, ends after it or for a new key,
and never holds for an empty key or a clock set back. `tests/test-omarr.sh`
engine probe: the first login meets a 503, and the row reads
`down|HTTP 503` with nothing held. The open panel's next 2 s poll logs in
again, meets the wrong password's 200 `Fails.`, shows `down|Login failed`
and stays so through 5 s of polling. The wrong password is sent exactly
twice (the 503 and the refusal), and nothing else goes to that qBittorrent
while the hold lasts. Saving the right password logs in at once and the row reads
"Idle".

**Rejected.** Backing off exponentially (2 s, 4 s, 8 s…): five failures
still come within a minute, which is qBittorrent's ban. Never retrying
until the credentials change: a qBittorrent that was misconfigured on its
own side would never recover without a settings edit, and one retry an hour
stays under five failures for hours. Showing "Login failed" but keeping the
`torrents/info` poll: with blank fields it is what triggers the `admin`
login, so the loop would remain. Holding on any non-2xx/3xx answer (this
plan's first version): a 502 or 503 while qBittorrent restarts behind a
proxy says nothing about the password, yet it held the right credentials
for an hour behind "Login failed", with no way to retry short of editing
them (see Review).

## 2. Todoist: a second edit or delete sent while the first runs is lost

**Evidence.** `deleteTask` and `editTask` (`haseen.todoist/Service.qml:414-430`)
each sent their request through their own Process (`deleteProc` `:584`,
`editProc` `:603`) by setting `command` and `running = true` (`api`,
`:107-113`), with no check and no queue. Completion used `actionQueue` and
checked `actionProc.running` (`:406`). A probe of Quickshell 0.3.2 (the
laptop's) showed what happens: a Process asked to
run while it runs starts the last command it was given once the current
one exits. Commands set in between are overwritten. So with two
back-to-back deletes both went out, but the first one's exit `refresh()`
could bring the second task back for a moment. With three, the middle one
never reached the server, and an edit lost that way is silently overwritten
by the refresh. On 9a9e82ab the engine check (three edits and three
deletes back to back) logged `POST tasks/a1|DELETE tasks/a4|DELETE
tasks/a6|POST tasks/a3`: the second edit and the second delete were lost,
and the list was fetched again three times.

**Fix.** Close, edit and delete share `actionQueue`. Each entry is
`{verb, taskId, method, path, body}`, sent one at a time in order through
`actionProc`. `deleteProc` and `editProc` are gone. A failed close still
undoes its strike-through and refreshes. A successful edit or delete sets
`refreshAfterActions`, and the list is fetched once the queue is empty, so
a fetch never brings back a task that is still queued for deletion.

**Test.** `tests/test-todoist.sh` engine probe: three edits and three
deletes back to back show at once and reach the server in order (`POST
tasks/a1|POST tasks/a2|POST tasks/a3|DELETE tasks/a4|DELETE tasks/a5|DELETE
tasks/a6`). Each edit sends its own text, the list is fetched no time
between the first and last and once after, and no error shows.

**Rejected.** Refusing an action while one runs: `x`, `y` on the next row
is a normal way to triage, and dropping it with a message is no better than
dropping it silently. A queue per verb: a delete that overtakes an edit of
the same task would reorder what the user did.

## 3. A service added mid-session notifies every row of its history

**Evidence.** `seeding` (`haseen.omarr/Service.qml:104`) starts true and is
cleared at `:1830` the first time the request queue drains. Nothing sets it
again, and no caller passed `commitSnapshot`'s `seedEvents` (`:549`).
`addService` (`:271-279`) only persists and polls. A Sonarr added later was
compared with `Model.emptySnapshot`, so `eventsFromPoll` (`Model.js:2548`)
emitted a grab or import for every history row, and `shouldNotify` passed
them (`notifyGrab`/`notifyImport` default on). A Jellyfin's recent items
and a Seerr's pending requests did the same. So did a URL change, since
`updateService` keeps the old snapshot under the same id. On 9a9e82ab the
engine check added a Sonarr with 3 old grabs: 3 notifications, then 4
after one new grab. The verifier's correction holds: a plugin started with
no services has not drained its queue, so its first service is seeded.
The flood needs services that already exist, as in the probe.

**Fix.** `listsAnswered` records, per service id, the URL the event lists
answered from and which lists (`activity`, `recent`, `pending`) have
answered. `firstAnswer(service, list)` is true the first time a list
answers for a service at its current URL, and the four committers
(`arr-history`, `sab-history`, `jellyfin-recent`, Seerr's pending batch)
pass it as `seedEvents`. A new service, or one pointed at a new URL, seeds
the rows it finds and notifies what happens after. `removeService` drops
the record. The startup `seeding` flag stays: it still covers the first
drain.

**Test.** `tests/test-omarr.sh` engine probe: with qBittorrent already
polled, a Sonarr added through `addService` whose history holds three
grabs sends no notification. When a fourth grab appears, exactly one
notification goes out ("Sonarr grabbed New Show").

**Rejected.** Setting `seeding` back to true on `addService`: it is global,
so an event from every other service in that window would be swallowed.
Seeding per service rather than per list: the lists answer in separate
requests, and a slow history after a quick queue would still flood.

## 4. Todoist: changing the bar count mode during a count fetch keeps the old mode's number

**Evidence.** `setBarCountMode` (`haseen.todoist/Service.qml:202-208`) sets
the mode and calls `refreshBarCount`, which returned at `:324` while
`barCountProc` ran. `barCountExited` (`:340-367`) stored the answer in
`barCountValue` (`:365`) without knowing which mode it counted. The old
mode's number then showed under the new label until the next refresh, 20
minutes later with the panel closed (`backgroundRefreshTimer`). A
multi-page fetch also asked for its next page with the new mode's path and
the old mode's cursor. On 9a9e82ab the engine check (Inbox, then All,
while the Inbox count ran) showed `1|false|Todoist: 1 total`.

**Fix.** The fetch records its mode (`barCountFetchMode`), and every page
of it asks for that mode. A count asked for while one runs sets
`barCountPending`, as `refreshPending` does for the list. An answer for a
mode that is no longer current is dropped and also sets the flag.
`continueBarCount` then starts the current mode's count instead of the next
page. `clearToken` clears the flag.

**Test.** `tests/test-todoist.sh` engine probe: switching to Inbox and then
All while the Inbox count runs leaves the request pending. The bar ends at
All's `2000|true|Todoist: 2000+ total`, and Inbox was asked only once.

**Rejected.** Killing the running count and starting the new one: a
SIGTERM'd curl reads as a failure, and `responseFailure` feeds the token
check from it. Dropping the stale answer without asking again: a settings
reload that changes the mode would leave the old number until the next
timer.

## Docs

`haseen.omarr/UPSTREAM.md` (per-list seeding under Notifications, a
qBittorrent login entry) and `haseen.todoist/UPSTREAM.md` (one queue for
close, edit and delete, the bar count's mode) describe the new behaviour.

## Review

Round 1 (Sonnet, request changes, one should-fix). The first version held
the credentials on any non-2xx/3xx login answer. A transient 502, 503,
504, 404 or 429 on `/api/v2/auth/login`, common when qBittorrent sits
behind a reverse proxy or a VPN container and restarts, then read "Login
failed" and sent nothing to that service for an hour although the
credentials were right; before this plan the next poll recovered, and
`forcePoll` did not clear the hold. Fixed by splitting the decision
(`Model.qbitLoginOutcome`): only a `Fails` body or a 401/403 holds; any
other answer clears the hold, shows its HTTP code and is retried on the
next poll. `Model.test.js` covers each code, and the engine probe now
starts with a 503 login that is shown as `HTTP 503`, holds nothing and is
followed by a fresh login. Against the first version's `Service.qml` the
two new engine checks fail (`down|Login failed|1` and one login instead of
two); they pass here.
