// A fake polkitd for a .rules file: loads it with a polkit object that records
// polkit.addRule, then runs every case through the rules in order, as polkitd
// does, until one returns a result. Prints one JSON object on stdout: the case
// name and "yes", "no", ... or "not_handled". The polkit API follows
// polkit(8) ("AUTHORIZATION RULES"): action.id, action.lookup(key) for the
// caller's details, subject.user, subject.isInGroup(), polkit.Result.*.
//
//   node polkit-harness.js RULES.rules CASES.json
//
// CASES.json is [{"name", "action": {"id", "details": {...}},
// "subject": {"user", "groups": [...], "local", "active"}}]. The rule runs in
// a fresh context with nothing but polkit, as in polkitd; polkit.spawn
// throws, so a rule that shells out fails here.
"use strict";
const fs = require("fs");
const vm = require("vm");

const [rulesFile, casesFile] = process.argv.slice(2);
const Result = {
    NO: "no", YES: "yes", AUTH_SELF: "auth_self", AUTH_SELF_KEEP: "auth_self_keep",
    AUTH_ADMIN: "auth_admin", AUTH_ADMIN_KEEP: "auth_admin_keep", NOT_HANDLED: null,
};
const rules = [];
const polkit = {
    Result,
    addRule: f => rules.push(f),
    addAdminRule: () => {},
    log: () => {},
    spawn: () => { throw new Error("polkit.spawn is not allowed here"); },
};
vm.runInNewContext(fs.readFileSync(rulesFile, "utf8"), { polkit }, { filename: rulesFile });

const report = {};
for (const c of JSON.parse(fs.readFileSync(casesFile, "utf8"))) {
    const details = c.action.details || {};
    const action = {
        id: c.action.id,
        lookup: key => (Object.prototype.hasOwnProperty.call(details, key) ? details[key] : undefined),
    };
    const s = c.subject || {};
    const subject = {
        user: s.user, pid: 4242, local: s.local !== false, active: s.active !== false,
        groups: s.groups || [],
        isInGroup: g => (s.groups || []).includes(g),
        isInNetGroup: () => false,
    };
    let result = null;
    for (const rule of rules) {
        const r = rule(action, subject);
        if (r !== undefined && r !== null) {
            result = r;
            break;
        }
    }
    report[c.name] = result === null ? "not_handled" : result;
}
process.stdout.write(JSON.stringify({ rules: rules.length, results: report }) + "\n");
