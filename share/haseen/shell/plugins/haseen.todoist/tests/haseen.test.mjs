import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// The helpers haseen added to Model.js (plan 097): request paths, the settings
// reader, quick-add text, priority tones and the Today section headers. Run
// as model.test.mjs runs upstream's: Model.js in a vm, globals read back.
const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8")
const ctx = vm.createContext({})
vm.runInNewContext(source + "\nthis.M = this", ctx)
const M = ctx.M
const plain = value => JSON.parse(JSON.stringify(value))

test("taskListPath: a path under /api/v1, one per view, paged at 200", () => {
  assert.equal(M.taskListPath("all", "", ""), "tasks?limit=200")
  assert.equal(M.taskListPath("today", "", ""), "tasks/filter?query=today%20%7C%20overdue&lang=en&limit=200")
  assert.equal(M.taskListPath("inbox", "", "c1"), "tasks/filter?query=%23Inbox&lang=en&limit=200&cursor=c1")
  assert.equal(M.taskListPath("custom", "#Work & p1", ""), "tasks/filter?query=%23Work%20%26%20p1&lang=en&limit=200")
  // An emptied filter falls back to the default view, as upstream's field does.
  assert.equal(M.taskListPath("custom", "  ", ""), M.taskListPath("today", "", ""))
  // Never a scheme or host: haseen-todoist.sh adds those, and refuses them.
  for (const view of ["all", "today", "inbox", "custom"])
    assert.doesNotMatch(M.taskListPath(view, "a/../b", "x y"), /^[a-z]+:|\/\/|\s/)
})

test("readSettings: preferences with bounds, and only whether a token exists", () => {
  const s = plain(M.readSettings(JSON.stringify({ apiToken: "secret", filter: "#Work", quickView: "inbox", barCountMode: "all", panelWidth: 9000, panelHeight: 10, keybind: "SUPER + Y" })))
  assert.deepEqual(s, { hasToken: true, filterQuery: "#Work", quickView: "inbox", barCountMode: "all", panelWidth: 700, panelHeight: 240 })
  assert.ok(!JSON.stringify(s).includes("secret"), "the token itself is never returned")
  assert.deepEqual(plain(M.readSettings("")), { hasToken: false, filterQuery: "today | overdue", quickView: "today", barCountMode: "hide", panelWidth: 340, panelHeight: 480 })
  assert.equal(M.readSettings('{"apiToken":"   "}').hasToken, false, "a blank token is no token")
  assert.equal(M.readSettings('{"quickView":"bogus","barCountMode":7}').quickView, "today")
  assert.equal(M.readSettings("{not json").hasToken, false)
  assert.equal(M.readSettings("[1,2]").panelWidth, 340)
})

test("quickAddText: due today unless the text names a date", () => {
  assert.equal(M.quickAddText("  buy milk "), "buy milk today")
  assert.equal(M.quickAddText("call Sam tomorrow 9am"), "call Sam tomorrow 9am")
  assert.equal(M.quickAddText("report {friday}"), "report {friday}")
  assert.equal(M.quickAddText("   "), "")
})

test("priorityTone: p1 urgent, p2 warning, p3 accent, p4 plain", () => {
  assert.deepEqual([4, 3, 2, 1, undefined].map(p => M.priorityTone(p)), ["urgent", "warning", "accent", "", ""])
})

test("sectionTitle: OVERDUE and TODAY headers on the Today view only", () => {
  const tasks = [
    { id: "1", due: { date: "2001-01-01" } },
    { id: "2", due: { date: "2001-01-02" } },
    { id: "3", due: { date: "2999-01-01" } }
  ]
  assert.equal(M.sectionTitle(tasks, 0, "today"), "OVERDUE · 2")
  assert.equal(M.sectionTitle(tasks, 1, "today"), "")
  assert.equal(M.sectionTitle(tasks, 2, "today"), "TODAY · 1")
  assert.equal(M.sectionTitle(tasks, 0, "all"), "")
  assert.equal(M.sectionTitle(tasks, 5, "today"), "")
})
