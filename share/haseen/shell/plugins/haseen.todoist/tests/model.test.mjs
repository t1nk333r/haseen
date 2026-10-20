import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// Model.js is the panel's pure half: shaping what curl got back into rows, and
// turning a response into a message. No QML/Qt types, so it runs here, with the
// globals it declares read back out of the context it ran in.
const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8")
const ctx = vm.createContext({})
vm.runInNewContext(source + "\nthis.M = this", ctx)
const M = ctx.M

// Objects and arrays built inside the vm carry that realm's prototypes, which
// deepStrictEqual refuses to match against this one's.
const list = value => Array.from(value)
const plain = value => JSON.parse(JSON.stringify(value))

test("Model.js exports the response and pagination helpers", () => {
  for (const name of ["parseCurlResponse", "parseJsonOrNull", "statusMessage", "tokenRejected",
                      "pageQuery", "parseTaskPage", "mergeTaskPage", "mergeTaskCountPage",
                      "emptyFetch", "errorMessageForExit", "sortedTasks", "taskIsOverdue",
                      "taskDueLabel", "sanitizeFilter", "formatRelativeTime"]) {
    assert.equal(typeof M[name], "function", `Model.js has no ${name}()`)
  }
})

// ---- the -w status line and the body it must not eat ----------------------

test("parseCurlResponse splits the -w status line off the body", () => {
  const page = M.parseCurlResponse('{"results":[{"id":"1"}]}\n200')
  assert.equal(page.status, 200)
  assert.equal(page.body, '{"results":[{"id":"1"}]}', "the status line is not part of the body")

  // A body that already ends in a newline leaves the status line on its own.
  const padded = M.parseCurlResponse('{"a":1}\n\n204')
  assert.equal(padded.status, 204)
  assert.equal(padded.body, '{"a":1}\n')

  // The documented error object is why -f had to go: it only arrives if curl
  // is allowed to keep an error body.
  const refused = M.parseCurlResponse('{"error_tag":"UNAUTHORIZED","http_code":401}\n401')
  assert.equal(refused.status, 401)
  assert.equal(JSON.parse(refused.body).error_tag, "UNAUTHORIZED")

  // A status with nothing before it: a 204, or an error the API explained
  // nowhere but the status line.
  const bare = M.parseCurlResponse("\n429")
  assert.equal(bare.status, 429)
  assert.equal(bare.body, "")

  // curl never reached HTTP, so there is no status line to split off — and the
  // caller has to treat that as a transport failure rather than a success.
  for (const text of ["", "   \n", "\n000"]) {
    assert.equal(M.parseCurlResponse(text).status, 0, `"${text}" is not an HTTP status`)
  }
  const bodyOnly = M.parseCurlResponse('{"results":[]}')
  assert.equal(bodyOnly.status, 0, "a response with no -w line reports no status at all")
  assert.equal(bodyOnly.body, '{"results":[]}', "and keeps what it got, for the caller to judge")
})

// ---- what the status means ------------------------------------------------

test("statusMessage is silent on success and names every failure class", () => {
  assert.equal(M.statusMessage(200, '{"results":[]}'), "")
  assert.equal(M.statusMessage(204, ""), "")
  assert.equal(M.statusMessage(0, ""), "", "no HTTP status is not a message of its own")

  // 401/403 — the token, said as such, with the API's own wording kept.
  const unauthorized = JSON.stringify({
    error_tag: "UNAUTHORIZED", error_code: 477, error: "Unauthorized",
    http_code: 401, error_extra: { retry_after: 3 },
  })
  const rejected = M.statusMessage(401, unauthorized)
  assert.match(rejected, /token/i)
  assert.match(rejected, /Unauthorized/, "the API's own explanation is not thrown away")
  assert.doesNotMatch(rejected, /rate limit/i, "a 401 is not a rate limit")
  assert.match(M.statusMessage(403, ""), /token/i)

  // 404 — the task is gone (the mutating paths' only 404).
  const gone = M.statusMessage(404, '{"error":"Not Found"}')
  assert.match(gone, /task/i)
  assert.doesNotMatch(gone, /token/i)

  // 429 — rate limited, with the delay the body gave and only that.
  const limited = M.statusMessage(429, '{"error_tag":"RATE_LIMITED","error_extra":{"retry_after":3}}')
  assert.match(limited, /rate limit/i)
  assert.match(limited, /3/, "retry_after from the body is honoured")
  const noDelay = M.statusMessage(429, "")
  assert.match(noDelay, /rate limit/i)
  assert.doesNotMatch(noDelay, /\d/, "no delay is invented when the body gives none")

  // 5xx — Todoist is failing, and which code it failed with.
  for (const code of [500, 503]) {
    assert.match(M.statusMessage(code, ""), new RegExp(String(code)))
  }

  // Anything else: the code, plus whatever the body called it.
  assert.match(M.statusMessage(418, '{"error":"teapot"}'), /418/)
  assert.match(M.statusMessage(418, '{"error":"teapot"}'), /teapot/)
  assert.match(M.statusMessage(400, '{"message":"Argument query is invalid"}'), /Argument query is invalid/)
  assert.match(M.statusMessage(400, '{"error_tag":"BAD_REQUEST"}'), /BAD_REQUEST/,
    "the machine-readable tag is the last resort")
  assert.match(M.statusMessage(418, ""), /418/, "even with no body at all")
  assert.match(M.statusMessage(502, "<html>Bad Gateway</html>"), /502/,
    "a body that is not JSON still gets an answer")
})

test("tokenRejected is exactly the statuses that mean the token was refused", () => {
  for (const code of [401, 403]) assert.equal(M.tokenRejected(code), true)
  for (const code of [0, 200, 204, 400, 404, 429, 500]) {
    assert.equal(M.tokenRejected(code), false, `HTTP ${code} does not mean a rejected token`)
  }
})

// ---- pagination -----------------------------------------------------------

test("pageQuery asks for the documented page size, then the cursor", () => {
  assert.equal(M.pageQuery(""), "limit=200", "200 is the documented maximum")
  assert.equal(M.pageQuery(null), "limit=200")
  assert.equal(M.pageQuery("abc"), "limit=200&cursor=abc")
  const cursor = M.pageQuery("a b&c=1").replace(/^limit=200&cursor=/, "")
  assert.equal(decodeURIComponent(cursor), "a b&c=1", "a cursor is a query value, not a fragment")
})

test("parseTaskPage reads results and the cursor, string or null", () => {
  const page = M.parseTaskPage('{"results":[{"id":"1"},{"id":"2"}],"next_cursor":"c1"}')
  assert.equal(list(page.results).length, 2)
  assert.equal(page.nextCursor, "c1")

  assert.equal(M.parseTaskPage('{"results":[],"next_cursor":null}').nextCursor, null)
  assert.equal(M.parseTaskPage('{"results":[]}').nextCursor, null, "a missing cursor ends the list")
  assert.equal(M.parseTaskPage('{"results":[],"next_cursor":""}').nextCursor, null, "an empty cursor is not one")
  assert.equal(list(M.parseTaskPage('{"next_cursor":null}').results).length, 0, "no results key is an empty page")

  assert.throws(() => M.parseTaskPage("<html>502 Bad Gateway</html>"),
    "a body that is not JSON has to fail, not read as an empty list")
  assert.throws(() => M.parseTaskPage(""))
})

test("mergeTaskPage accumulates pages and stops at the cap", () => {
  const page = (ids, cursor) => M.parseTaskPage(JSON.stringify({
    results: ids.map(id => ({ id })), next_cursor: cursor,
  }))

  let state = M.mergeTaskPage(null, page(["1", "2"], "c1"))
  assert.equal(list(state.tasks).length, 2)
  assert.equal(state.cursor, "c1")
  assert.equal(state.pages, 1)

  state = M.mergeTaskPage(state, page(["3"], "c2"))
  assert.equal(list(state.tasks).map(t => t.id).join(","), "1,2,3", "rows accumulate across pages")
  assert.equal(state.cursor, "c2")

  state = M.mergeTaskPage(state, page(["4"], null))
  assert.equal(state.cursor, null, "a null cursor ends the sequence")
  assert.equal(list(state.tasks).length, 4)
  assert.equal(state.pages, 3)

  // A cursor that never ends must not keep the loop alive: the tenth page ends
  // the sequence even though the API asked for another one.
  let runaway = M.emptyFetch()
  for (let i = 0; i < 10; i++) runaway = M.mergeTaskPage(runaway, page([String(i)], "more"))
  assert.equal(runaway.pages, 10)
  assert.equal(runaway.cursor, null, "the page cap stops a runaway cursor")
  assert.equal(list(runaway.tasks).length, 10)

  // The count-only fold is the same sequence without the rows: the bar badge
  // wants the size of the list, which is more than one page of it.
  let counted = M.mergeTaskCountPage(null, page(["1", "2"], "c1"))
  counted = M.mergeTaskCountPage(counted, page(["3"], null))
  assert.equal(counted.count, 3)
  assert.equal(counted.cursor, null)
  assert.equal(counted.tasks, undefined, "the count-only fold keeps no rows")

  // A cap and a real end both null the cursor, and only `truncated` tells them
  // apart. The panel's TASKS stat reads it so a floor never reads as a total —
  // the same silent lie the pagination work existed to remove, one threshold up.
  assert.equal(counted.truncated, false, "a fetch the API ended is not truncated")
  let finished = M.emptyFetch()
  finished = M.mergeTaskPage(finished, page(["1"], null))
  assert.equal(finished.truncated, false)
  let capped = M.emptyFetch()
  for (let i = 0; i < 10; i++) capped = M.mergeTaskPage(capped, page([String(i)], "more"))
  assert.equal(capped.cursor, null)
  assert.equal(capped.truncated, true, "stopping at the cap is not the same as finishing")
  // ... and it stays true through a later page that does end, because those rows
  // are still only part of the list the cap cut short.
  const cappedThenEnd = M.mergeTaskPage(capped, page(["x"], null))
  assert.equal(cappedThenEnd.truncated, true, "the caveat travels with the data")
})

// ---- the helpers this change touched --------------------------------------

test("errorMessageForExit covers the transport failures curl still exits non-zero for", () => {
  assert.match(M.errorMessageForExit(28, ""), /too long/i)
  assert.match(M.errorMessageForExit(6, "curl: (6) Could not resolve host: api.todoist.com"), /connection/i)
  assert.match(M.errorMessageForExit(22, "curl: (22) boom"), /boom/, "curl's own first line is kept")

  // The token message comes from the status the API returned, never from
  // digits that happen to be in curl's stderr.
  assert.doesNotMatch(
    M.errorMessageForExit(22, "curl: (22) The requested URL returned error: 401"), /token/i)
})

test("sortedTasks keeps undated tasks last and breaks ties by priority", () => {
  const sorted = list(M.sortedTasks([
    { id: "c", content: "C", priority: 1 },
    { id: "a", content: "A", due: { date: "2026-01-02" }, priority: 1 },
    { id: "b", content: "B", due: { date: "2026-01-01" }, priority: 1 },
    { id: "d", content: "D", due: { date: "2026-01-01" }, priority: 4 },
  ]))
  assert.equal(sorted.map(t => t.id).join(","), "d,b,a,c")
  assert.equal(list(M.sortedTasks(null)).length, 0)
})

test("taskIsOverdue reads the date out of either due.date shape", () => {
  assert.equal(M.taskIsOverdue(null), false)
  assert.equal(M.taskIsOverdue({}), false)
  assert.equal(M.taskIsOverdue({ due: { date: "1999-01-01" } }), true)
  assert.equal(M.taskIsOverdue({ due: { date: "1999-01-01T10:00:00Z" } }), true)
  assert.equal(M.taskIsOverdue({ due: { date: M.todayIsoDate() } }), false)
  assert.equal(M.taskIsOverdue({ due: { date: "2999-01-01" } }), false)
})

test("taskDueLabel prefers Todoist's phrasing and falls back to the date", () => {
  assert.equal(M.taskDueLabel({ due: { string: "tomorrow at 10:00", date: "2026-01-01" } }), "tomorrow at 10:00")
  assert.equal(M.taskDueLabel({ due: { date: "2026-01-01T10:00:00Z" } }), "2026-01-01")
  assert.equal(M.taskDueLabel({}), "")
  assert.equal(M.taskDueLabel(null), "")
})

test("sanitizeFilter falls back to the default view only when cleared", () => {
  assert.equal(M.sanitizeFilter(""), "today | overdue")
  assert.equal(M.sanitizeFilter("   "), "today | overdue")
  assert.equal(M.sanitizeFilter(null), "today | overdue")
  assert.equal(M.sanitizeFilter("  #Inbox  "), "#Inbox")
})

test("formatRelativeTime reads the header's SYNCED stat", () => {
  assert.equal(M.formatRelativeTime(0), "never")
  const now = Date.now()
  assert.equal(M.formatRelativeTime(now), "just now")
  assert.equal(M.formatRelativeTime(now - 3 * 60 * 1000), "3m ago")
  assert.equal(M.formatRelativeTime(now - 5 * 60 * 60 * 1000), "5h ago")
  assert.equal(M.formatRelativeTime(now - 3 * 24 * 60 * 60 * 1000), "3d ago")
})
