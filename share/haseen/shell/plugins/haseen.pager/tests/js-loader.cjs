// Loads the plugin's .pragma library files into a node vm context, resolving
// their `.import "X.js" as X` lines. From omapager's tests/js-loader.cjs
// (https://github.com/njpatel/omapager, MIT, Copyright (c) 2026 Neil Jagdish Patel).
const fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const cache = {};
function load(name) {
  if (cache[name]) return cache[name];
  const scope = {console, Qt: {openUrlExternally: u => u}};
  const code = fs.readFileSync(path.join(__dirname, '..', name + '.js'), 'utf8')
    .replace(/^\.pragma.*$/mg, '')
    .replace(/^\.import "([^"]+)" as (\w+)$/mg, (_, file, alias) => {
      scope[alias] = load(file.replace(/\.js$/, '')); return '';
    });
  vm.createContext(scope); vm.runInContext(code, scope); return cache[name] = scope;
}
module.exports = load;
