// Pure data helpers for haseen.todoist: response shaping, sorting, paging,
// error wording and the settings file's shape. No QML types, so tests/ runs it
// under node; the service owns everything stateful (processes, files, timers).
//
// Adapted from Model.js in omarchy-todoist (MIT, Copyright (c) 2026
// aryan-techie), as the owner's fork t1nk33r.todoist 1.14.0; see LICENSE and
// UPSTREAM.md beside this file. haseen adds the request paths, the settings
// reader, the priority tones and the state-directory choice at the end.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109). The helpers
// that compose a line take the I18n singleton as an optional last argument
// (`Model.formatRelativeTime(ms, I18n)`) and fill its translation; without
// it they return English, which is what tests/ reads.
function N_(text) { return text }
// A counted pair, marked for tools/i18n.py: countText() picks the form.
function N_n(singular, plural) { return [singular, plural] }

// %1..%9 replaced in one pass, as I18n.tr fills them.
function fillText(text, args) {
  var list = args || []
  return String(text).replace(/%([1-9])/g, function(whole, digit) {
    var value = list[Number(digit) - 1]
    return value === undefined || value === null ? whole : String(value)
  })
}

function trText(i18n, text, args) {
  var list = args || []
  return i18n ? i18n.tr.apply(i18n, [text].concat(list)) : fillText(text, list)
}

function countText(i18n, forms, count, args) {
  var list = args || []
  if (i18n) return i18n.tn.apply(i18n, [forms[0], forms[1], count].concat(list))
  return fillText(Number(count) === 1 ? forms[0] : forms[1], [count].concat(list))
}

function safeTrim(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

// Todoist filter query (e.g. "today | overdue"). Falls back to the default
// due/overdue view whenever the user clears the field.
function sanitizeFilter(filter) {
  var trimmed = safeTrim(filter)
  return trimmed === "" ? "today | overdue" : trimmed
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// due.date is either a plain "YYYY-MM-DD" or a full ISO timestamp depending
// on whether the task has a time component. The first 10 characters are the
// date either way.
function isoDatePrefix(dateStr) {
  var s = String(dateStr || "")
  return s.length >= 10 ? s.substring(0, 10) : s
}

function todayIsoDate() {
  var now = new Date()
  return now.getFullYear() + "-" + pad2(now.getMonth() + 1) + "-" + pad2(now.getDate())
}

// Prefers Todoist's own human phrasing ("tomorrow at 10:00") and only falls
// back to the raw date when a task has a due date but no string form.
function taskDueLabel(task) {
  if (!task || !task.due) return ""
  return task.due.string || isoDatePrefix(task.due.date)
}

function taskIsOverdue(task) {
  if (!task || !task.due || !task.due.date) return false
  return isoDatePrefix(task.due.date) < todayIsoDate()
}

// Overdue/due-soonest first, undated tasks last; priority breaks ties within
// the same date, then content for a stable order.
function sortedTasks(tasks) {
  var list = (tasks || []).slice()
  list.sort(function(a, b) {
    var aDue = a && a.due && a.due.date ? isoDatePrefix(a.due.date) : ""
    var bDue = b && b.due && b.due.date ? isoDatePrefix(b.due.date) : ""
    if (aDue !== bDue) {
      if (aDue === "") return 1
      if (bDue === "") return -1
      return aDue < bDue ? -1 : 1
    }

    var aPriority = a && typeof a.priority === "number" ? a.priority : 1
    var bPriority = b && typeof b.priority === "number" ? b.priority : 1
    if (aPriority !== bPriority) return bPriority - aPriority

    var aContent = (a && a.content) || ""
    var bContent = (b && b.content) || ""
    return aContent < bContent ? -1 : (aContent > bContent ? 1 : 0)
  })
  return list
}

// Heuristic only — Quick Add's own NLP (see /tasks/quick) does the real
// parsing server-side. This just decides whether *we* should tack on
// " today" before sending, so a bare "Buy milk" defaults to due today
// instead of no due date, without stomping on a date the user already typed
// ("tomorrow", "next Monday", "3/5", "at 5pm", a deadline in {}, etc.).
var DUE_HINT_RE = /\b(today|tonight|tomorrow|tmrw|tom|next|mon|tue|wed|thu|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b|\d{1,2}[\/\-]\d{1,2}|\d{1,2}\s*(am|pm)\b|\bat\s+\d|\bin\s+\d+\s*(day|week|hour|min)|\{[^}]*\}/i

function quickAddHasDueHint(text) {
  return DUE_HINT_RE.test(text)
}

// Relative time for the header's SYNCED stat. `epochMs` is 0 before the
// first successful fetch ever lands.
function formatRelativeTime(epochMs, i18n) {
  if (!epochMs) return trText(i18n, N_("never"))
  var deltaSec = Math.max(0, Math.round((Date.now() - epochMs) / 1000))
  if (deltaSec < 45) return trText(i18n, N_("just now"))
  var deltaMin = Math.round(deltaSec / 60)
  if (deltaMin < 60) return countText(i18n, N_n("%1m ago", "%1m ago"), deltaMin)
  var deltaHour = Math.round(deltaMin / 60)
  if (deltaHour < 24) return countText(i18n, N_n("%1h ago", "%1h ago"), deltaHour)
  var deltaDay = Math.round(deltaHour / 24)
  return countText(i18n, N_n("%1d ago", "%1d ago"), deltaDay)
}

// ---- Reading a response. Every request is made with -w "\n%{http_code}", so
//      the HTTP status is the last line of stdout and everything above it is
//      the body. That is also why curl is *not* run with -f: the flag makes
//      curl throw the body away on an error, and the body is where the API
//      documents what went wrong (error_tag, error, error_extra.retry_after).

// Splits curl's write-out off the body. A `status` of 0 means curl reported no
// HTTP status at all: the request got no response, and the exit code plus
// curl's own stderr are the only signal there is. The body comes back as text —
// each path parses it once, into the shape it actually needs.
function parseCurlResponse(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).replace(/\s+$/, "")
  var breakAt = text.lastIndexOf("\n")
  var tail = breakAt === -1 ? text : text.substring(breakAt + 1)
  if (!/^\d{3}$/.test(tail)) return { status: 0, body: text }
  return { status: parseInt(tail, 10), body: breakAt === -1 ? "" : text.substring(0, breakAt) }
}

// A body that may not be JSON at all, for the one caller that has to tolerate
// whatever came back: a failure body is not worth an error line of its own.
function parseJsonOrNull(bodyText) {
  try { return JSON.parse(String(bodyText === undefined || bodyText === null ? "" : bodyText)) }
  catch (e) { return null }
}

// The API's own wording for a failure, in the order the spec names the fields.
// "" when the response carried no such object — an HTML error page is not
// worth pasting into a 340px panel.
function apiErrorText(json) {
  if (!json || typeof json !== "object") return ""
  var candidates = [json.error, json.message, json.error_tag]
  for (var i = 0; i < candidates.length; i++) {
    var text = safeTrim(candidates[i])
    if (text !== "") return text
  }
  return ""
}

// The delay a 429 carries in its body (the docs also send a Retry-After
// header, which -w does not capture). 0 when the body gave none.
function retryDelaySeconds(json) {
  if (!json || typeof json !== "object" || !json.error_extra) return 0
  var value = Number(json.error_extra.retry_after)
  return isFinite(value) && value > 0 ? Math.ceil(value) : 0
}

// What a finished request means for the user: null when it succeeded, else
// the failure the panel shows, as an English template and its arguments
// ({text, args}; failureText() fills it, in the interface language when QML
// passes I18n). Only the statuses these endpoints document get their own
// wording — 401/403/404 (the spec, per path) and the project-wide
// 429/500/503 — and the rest still say which code came back and what the body
// called it. `status` 0 has no failure here: that is curl never reaching
// HTTP, which is exitFailure's case.
function statusFailure(status, bodyText) {
  var code = Number(status) || 0
  if (code === 0) return null
  if (code >= 200 && code < 300) return null

  var detail = apiErrorText(parseJsonOrNull(bodyText))

  if (code === 401 || code === 403)
    return detail === ""
      ? failure(N_("Todoist rejected the API token — check it in Settings."))
      : failure(N_("Todoist rejected the API token — check it in Settings. (%1)"), [detail])
  if (code === 404)
    return detail === ""
      ? failure(N_("That task is gone — it was deleted or completed somewhere else."))
      : failure(N_("That task is gone — it was deleted or completed somewhere else. (%1)"), [detail])
  if (code === 429) {
    var wait = retryDelaySeconds(parseJsonOrNull(bodyText))
    return wait > 0
      ? failure(N_n("Todoist is rate limiting this widget — try again in %1s.", "Todoist is rate limiting this widget — try again in %1s."), [], wait)
      : failure(N_("Todoist is rate limiting this widget — try again in a moment."))
  }
  if (code >= 500)
    return detail === ""
      ? failure(N_("Todoist is failing right now (HTTP %1)."), [code])
      : failure(N_("Todoist is failing right now (HTTP %1). %2"), [code, detail])
  return detail === ""
    ? failure(N_("Todoist answered HTTP %1."), [code])
    : failure(N_("Todoist answered HTTP %1: %2"), [code, detail])
}

// A failure for the panel: text is an English template (or, with count, the
// N_n pair whose form count picks), args fill %1.. (after the count).
function failure(text, args, count) {
  var out = { text: text, args: args || [] }
  if (count !== undefined) out.count = count
  return out
}

// The line a failure shows; "" for none.
function failureText(f, i18n) {
  if (!f) return ""
  return f.count !== undefined ? countText(i18n, f.text, f.count, f.args) : trText(i18n, f.text, f.args)
}

// statusFailure as an English line, "" on success.
function statusMessage(status, bodyText) {
  return failureText(statusFailure(status, bodyText))
}

// The statuses that mean the token itself was refused, as opposed to the
// request being wrong. The bar mark dims on exactly these.
function tokenRejected(status) {
  var code = Number(status) || 0
  return code === 401 || code === 403
}

// curl's own failures: DNS, no route, a timeout, a fetch that got no answer at
// all. Any response the API did send — success or not — is statusFailure's job
// instead.
function exitFailure(exitCode, stderrText) {
  var text = String(stderrText || "")
  if (text.indexOf("Could not resolve host") !== -1 || text.indexOf("Couldn't connect") !== -1
    || text.indexOf("Failed to connect") !== -1 || text.indexOf("Network is unreachable") !== -1)
    return failure(N_("Couldn't reach Todoist — check your connection."))
  if (exitCode === 28) return failure(N_("Todoist took too long to respond."))
  var firstLine = text.split("\n")[0]
  return firstLine !== ""
    ? failure(N_("Something went wrong talking to Todoist: %1"), [firstLine])
    : failure(N_("Something went wrong talking to Todoist."))
}

// exitFailure as an English line.
function errorMessageForExit(exitCode, stderrText) {
  return failureText(exitFailure(exitCode, stderrText))
}

// ---- Pagination. GET /tasks and /tasks/filter take `limit` (default 50,
//      maximum 200) and `cursor` and answer {results, next_cursor}, where
//      next_cursor is a string or null. Their default page size is what caps
//      the All view, the All badge and the TASKS stat today.
var TASK_PAGE_LIMIT = 200
// A cursor that never ends must not keep the panel looping. Ten pages is 2000
// tasks, far past anything a bar widget is for.
var TASK_PAGE_CAP = 10

// The query every list request carries: the documented maximum page size, plus
// the cursor for each page after the first.
function pageQuery(cursor) {
  var query = "limit=" + TASK_PAGE_LIMIT
  var value = safeTrim(cursor)
  if (value !== "") query += "&cursor=" + encodeURIComponent(value)
  return query
}

// The state a fetch starts from. `cursor` is the page to ask for next, so null
// means there is nothing more to fetch — and `truncated` is false, because a
// fetch that never ran has not hit the cap. (A finished fetch resets to null,
// not to this shape.)
function emptyFetch() {
  return { tasks: [], count: 0, cursor: null, pages: 0, truncated: false }
}

// One page of a paginated list. Throws on a body that is not JSON: an empty
// list and an unreadable answer are different things, and only one of them is
// worth an error. A missing `results` is an empty page; a missing or empty
// `next_cursor` means the list ended.
function parseTaskPage(bodyText) {
  var parsed = JSON.parse(String(bodyText === undefined || bodyText === null ? "" : bodyText))
  var cursor = parsed ? parsed.next_cursor : null
  return {
    results: parsed && Array.isArray(parsed.results) ? parsed.results : [],
    nextCursor: typeof cursor === "string" && cursor !== "" ? cursor : null
  }
}

function foldPage(state, page, keepTasks) {
  var previous = state || {}
  var pages = (previous.pages || 0) + 1
  var capped = pages >= TASK_PAGE_CAP && page.nextCursor !== null
  var next = {
    pages: pages,
    count: (previous.count || 0) + page.results.length,
    // The cap ends the sequence even when the API asked for another page, and a
    // capped count must not read as a total — that is D1 again, just at a higher
    // threshold. `truncated` carries the reason out so the caller can say so.
    cursor: capped ? null : page.nextCursor,
    truncated: capped || previous.truncated === true
  }
  if (keepTasks) next.tasks = (previous.tasks || []).concat(page.results)
  return next
}

// Folds one page (from parseTaskPage) into the fetch in progress: `state` is
// what the previous call returned, or null for the first page. The result's
// `cursor` is the page to ask for next — null once the API says there is none,
// and also once the page cap is reached, so a cursor that never ends cannot
// keep the loop alive; `truncated` tells those two apart.
function mergeTaskPage(state, page) {
  return foldPage(state, page, true)
}

// The same fold for a caller that only wants the size of the list (the bar
// badge): rows are counted and dropped instead of concatenated page after page.
function mergeTaskCountPage(state, page) {
  return foldPage(state, page, false)
}

// ---- haseen additions (plan 097) -------------------------------------------

// The API path (under https://api.todoist.com/api/v1/) for a view's list:
// "all" is plain /tasks, the others /tasks/filter with a canned or the saved
// custom query. haseen-todoist.sh adds the host, so a path is all the shell
// ever hands it.
function taskListPath(view, filterQuery, cursor) {
  var path = view === "all" ? "tasks"
    : "tasks/filter?query=" + encodeURIComponent(view === "inbox" ? "#Inbox"
      : view === "custom" ? sanitizeFilter(filterQuery)
      : "today | overdue") + "&lang=en"
  return path + (path.indexOf("?") === -1 ? "?" : "&") + pageQuery(cursor)
}

// A bare quick-add with no date hint is due today rather than undated.
function quickAddText(content) {
  var text = safeTrim(content)
  if (text === "") return ""
  return quickAddHasDueHint(text) ? text : text + " today"
}

var QUICK_VIEWS = ["today", "inbox", "all", "custom"]
var BAR_COUNT_MODES = ["hide", "today", "inbox", "all"]

function clampPanelWidth(value) {
  var n = Number(value)
  return isFinite(n) ? Math.max(260, Math.min(700, Math.round(n))) : 340
}

function clampPanelHeight(value) {
  var n = Number(value)
  return isFinite(n) ? Math.max(240, Math.min(800, Math.round(n))) : 480
}

// The settings file as the panel uses it. The token itself is not returned,
// only whether there is one: the shell never keeps it, haseen-todoist.sh reads
// it from the file for each request.
function readSettings(text) {
  var parsed = null
  try { parsed = JSON.parse(String(text === undefined || text === null ? "" : text) || "{}") } catch (e) { parsed = null }
  var data = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  return {
    hasToken: typeof data.apiToken === "string" && safeTrim(data.apiToken) !== "",
    filterQuery: typeof data.filter === "string" ? sanitizeFilter(data.filter) : "today | overdue",
    quickView: QUICK_VIEWS.indexOf(data.quickView) !== -1 ? data.quickView : "today",
    barCountMode: BAR_COUNT_MODES.indexOf(data.barCountMode) !== -1 ? data.barCountMode : "hide",
    panelWidth: typeof data.panelWidth === "number" ? clampPanelWidth(data.panelWidth) : 340,
    panelHeight: typeof data.panelHeight === "number" ? clampPanelHeight(data.panelHeight) : 480
  }
}

// Todoist's priority (4 = p1, the most urgent, down to 1 = none) as a Theme
// role: upstream used Todoist's own red, amber and blue, haseen's themes give
// the same three meanings.
function priorityTone(priority) {
  var p = Number(priority) || 0
  if (p === 4) return "urgent"
  if (p === 3) return "warning"
  if (p === 2) return "accent"
  return ""
}

// The view's section header over the task list: OVERDUE and TODAY groups on
// the Today view (tasks come sorted, so each group is contiguous), the view's
// name elsewhere is shown once above the list instead.
function sectionTitle(tasks, index, view, i18n) {
  var list = tasks || []
  if (view !== "today" || index < 0 || index >= list.length) return ""
  var overdue = taskIsOverdue(list[index])
  if (index > 0 && taskIsOverdue(list[index - 1]) === overdue) return ""
  var overdueCount = 0
  for (var i = 0; i < list.length; i++) if (taskIsOverdue(list[i])) overdueCount++
  return overdue ? trText(i18n, N_("OVERDUE · %1"), [overdueCount])
    : trText(i18n, N_("TODAY · %1"), [list.length - overdueCount])
}
