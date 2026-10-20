// From the tests of the owner's fork t1nk33r.vpn of jkoestinger/omarchy-vpn
// (MIT, Copyright (c) 2026 Justin Köstinger); see ../LICENSE. Unchanged by the
// haseen port (plan 096); tests/test-vpn.sh runs them with node.
// The model files are where every assumption about how a VPN CLI formats its
// output lives, and they are the only half of the widget that runs without a
// QML engine. This runs the suite over them:
//
//   node tests/run.js
//
// No dependencies and no test framework: the plugin ships no package.json and
// is not built, so a test suite that needed installing would not get run.
//
// Every tests/model/*.test.js file is picked up automatically, so adding a
// backend means adding a file here rather than editing this one. Files
// directly under tests/ are picked up the same way: they are the ones whose
// subject is the tree rather than one model — see qml.test.js.

const fs = require("fs")
const path = require("path")
const harness = require("./harness.js")

function suite(dir, files) {
  return files.filter(name => name.endsWith(".test.js")).sort().map(name => path.join(dir, name))
}

const models = path.join(__dirname, "model")
const files = suite(models, fs.readdirSync(models))
  .concat(suite(__dirname, fs.readdirSync(__dirname)))

if (files.length === 0) {
  console.error("no test files found in tests/ or tests/model/")
  process.exit(1)
}

for (const file of files) require(file)

process.exit(harness.report())
