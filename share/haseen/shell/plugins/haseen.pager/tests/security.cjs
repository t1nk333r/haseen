// Pure-JS regression tests for Detect/Markup/Security/Store/Layout, run by
// tests/test-pager.sh under node. The upstream sections are from omapager's
// tests/security.cjs (https://github.com/njpatel/omapager, MIT, Copyright (c)
// 2026 Neil Jagdish Patel); the Omarchy exec-argv cases are dropped with the
// feature, and the sections after "haseen" below are new.
const assert=require('node:assert/strict'), fs=require('node:fs'), load=require('./js-loader.cjs');
const S=load('Security'), M=load('Markup'), D=load('Detect'), Store=load('Store');
const bad=['https://paypal.com@evil.example','https://user:pass@example.com','javascript:alert(1)','file:///etc/passwd','smb://server/share','data:text/html,test','https://example.com/\n','https://example.com/%0d%0a','https://example.com/%250a','https://example.com%40evil.example','https://[::1]','https://127.1','https://éxample.com','https://example..com','https://example.com:99999','https://example.com\\@evil.example','https://example.com/'+ 'x'.repeat(4096)];
for (const u of bad) {
 assert.equal(S.safeExternalUrl(u),'',u);
 assert.equal(M.linkable(u),false,u);
 assert.equal(S.openExternalUrl(u),false,u);
 assert.ok(!M.render('<a href="'+u+'">click</a>').includes('<a href='),u);
 for (const detected of D.links(u)) assert.ok(S.safeHttpUrl(detected));
}
for (const u of ['https://example.com','http://example.com/path?q=1','https://xn--bcher-kva.example','https://example.com/a%40b','mailto:user@example.com']) assert.ok(S.safeExternalUrl(u),u);
assert.equal(S.safeHttpUrl('HTTPS://Example.COM.:443/a'),'https://example.com:443/a');
assert.equal(S.safeMailtoUrl('mailto:user@example.com?attach=/etc/passwd'),'');
for(const payload of ['<img src="file:///etc/passwd">','<svg><image href="https://example.com"/></svg>','<script>alert(1)</script>','<iframe src="x">','https://example.com/"onmouseover="x']) {
 const rendered=M.render(payload);
 assert.ok(!/<(?:img|svg|script|iframe|object|embed|style)\b/i.test(rendered),rendered);
 assert.ok(!/<a[^>]+onmouseover=/i.test(rendered),rendered);
}
{ // Escaped sender markup must not leak into collapsed or restored previews.
 const body='Thread in #support: &lt;b&gt;Sam&lt;/b&gt;&lt;br/&gt;the preview is readable &amp; compact';
 const expected='Thread in #support: Sam the preview is readable & compact';
 const row=Store.snapshot({appName:'Slack',summary:'Slack',body},'markup',{Normal:1});
 assert.equal(row.bodyLine,expected);
 const nested=body.replace(/&/g,'&amp;');
 assert.equal(Store.restored({key:'markup',body:nested,bodyLine:'stale preview'}).bodyLine,expected);
 const literals='List&lt;String&gt;: Sam &lt;sam@example.com&gt; asks if 3 &lt; 5\n&amp; 5 &gt; 2; &lt;3';
 const literalLine='List<String>: Sam <sam@example.com> asks if 3 < 5 & 5 > 2; <3';
 assert.equal(Store.snapshot({body:literals},'literal',{Normal:1}).bodyLine,literalLine);
 assert.equal(Store.restored({key:'literal',body:literals,bodyLine:'stale preview'}).bodyLine,literalLine);
 assert.equal(M.oneLine('<b>Sam</b><br/><a href="https://example.com">read &lt;details&gt;</a>'),
              'Sam read <details>');
 assert.equal(M.oneLine('&lt;img src="file:///etc/passwd"&gt; &lt;b class="literal"&gt;'),
              '<img src="file:///etc/passwd"> <b class="literal">');
 // Reverse only our own escaping; do not add a fourth sender-decoding pass.
 assert.equal(M.oneLine('&amp;amp;amp;lt;b&amp;amp;amp;gt;'), '&lt;b&gt;');
}
for (const body of ['Your verification code is 938271','Your code is 938 271','Your code is 938-271','Your code is &#57;38271','Your code is A9F3K2']) {
 const row=Store.snapshot({appName:'Test',summary:'Verification',body},'test', {Normal:1});
 const saved=Store.sanitiseForPersistence(row);
 for(const secret of ['938271','938 271','938-271','A9F3K2']) assert.ok(!JSON.stringify(saved).includes(secret));
}
{ // Literal attributes must not move legacy/raw-only codes outside the scan window.
 const body='Your code is <span title="'+'x'.repeat(100)+'">938271</span>';
 for (const entry of [{body}, {rawBody:body.replace(/</g,'&lt;').replace(/>/g,'&gt;')}]) {
  const saved=Store.sanitiseForPersistence(entry);
  assert.equal(saved.body,'[redacted]');
  assert.ok(!JSON.stringify(saved).includes('938271'));
 }
}
assert.equal(Store.snapshot({body:'x'.repeat(100000),summary:'y'.repeat(3000)},'test',{Normal:1}).body.length,32768);
assert.equal(Store.normalise({image:'file:///etc/passwd',stored_image:'/etc/passwd'}).image,'');
assert.equal(Store.normalise({body:'hello',bodyRich:'<img src="x">'}).bodyRich,'hello');
const start=Date.now();
for (const text of ['<'.repeat(32768),'&amp;'.repeat(6500),'9'.repeat(32768), 'https://'.repeat(4000)]) { M.render(text); D.scan('',text); }
assert.ok(Date.now()-start < 3000,'parsers exceeded 3-second budget');
// Deterministic generated corpus, never personal notifications.
let seed=17;
for(let i=0;i<1000;i++) {
 let s=''; for(let j=0;j<80;j++){seed=(seed*1664525+1013904223)>>>0;s+=String.fromCharCode(seed%128);}
 const u=S.safeExternalUrl(s); if(u) assert.equal(S.safeExternalUrl(u),u);
 assert.ok(!/<(?:img|script|iframe|object|svg)\b/i.test(M.render(s)));
}
for (const u of JSON.parse(fs.readFileSync(__dirname+'/corpus/urls.json'))) assert.equal(S.safeExternalUrl(u),'');
for (const text of JSON.parse(fs.readFileSync(__dirname+'/corpus/markup.json'))) assert.ok(!/<(?:img|svg|script|iframe|object)\b/i.test(M.render(text)));
for (const text of JSON.parse(fs.readFileSync(__dirname+'/corpus/codes.json'))) {
 const row=Store.snapshot({summary:'Verification',body:text},'fixture',{Normal:1});
 assert.equal(Store.sanitiseForPersistence(row).body,'[redacted]');
}

// Execute the production focus function: hostile compositor metadata must not
// become dispatch syntax. The only dispatchable value is a validated address.
{
  const vm=require('node:vm'), source=fs.readFileSync(__dirname+'/../Service.qml','utf8');
  const focus=source.match(/function focusWindow\(win\) \{[\s\S]*?\n    \}/)[0];
  for (const usingLua of [true, false]) {
    const calls=[], scope={Hyprland:{usingLua, dispatch:x=>calls.push(x)}};
    vm.createContext(scope);vm.runInContext(focus,scope);
    scope.focusWindow({wmClass:'x\\"}); os.execute("bad") --'});
    scope.focusWindow({address:'0x123);bad()',wmClass:'x'});
    assert.equal(calls.length,0);
    scope.focusWindow({address:'0x123abc'});assert.equal(calls.length,1);
    assert.equal(calls[0], usingLua ? 'hl.dsp.focus({window = hl.get_window("address:0x123abc")})' : 'focuswindow address:0x123abc');
  }
}

// PR 4 review finding 4 (P2): canonicalHostname() only rejected a last label
// of plain decimal digits ("127.0.0.1"), so a WHATWG-style numeric label
// using 0x-prefixed hex ("0x7f.0x0.0x0.0x1") slipped through as if it were
// an ordinary hostname, even though a real URL parser canonicalises it to a
// numeric address. Node's own URL implements the same WHATWG algorithm, so
// it is used here to prove the risk is real - not just asserted - before
// checking our policy rejects the un-canonicalised form outright.
{
  const NodeURL = require('node:url').URL;
  const hexQuad = 'http://0x7f.0x0.0x0.0x1/';
  const canon = new NodeURL(hexQuad).hostname;
  assert.equal(canon, '127.0.0.1', 'sanity: this environment\'s URL parser must actually canonicalise hex-quad host forms, or this test proves nothing');
  assert.equal(S.safeHttpUrl(hexQuad), '', 'review_p2_hex_ipv4_rejected');
  assert.equal(S.safeHttpUrl('http://0xa.0x0.0x0.0x1/'), '', 'review_p2_hex_ipv4_rejected');
  assert.equal(new NodeURL('http://0xa.0x0.0x0.0x1/').hostname, '10.0.0.1');
}
{
  const octalQuad = 'http://0177.0.0.1/';
  assert.equal(new (require('node:url').URL)(octalQuad).hostname, '127.0.0.1',
    'sanity: this environment\'s URL parser must actually canonicalise octal host forms, or this test proves nothing');
  assert.equal(S.safeHttpUrl(octalQuad), '', 'review_p2_octal_ipv4_rejected');
  assert.equal(S.safeHttpUrl('http://0177.00.00.01/'), '', 'review_p2_octal_ipv4_rejected');
}
{
  const NodeURL = require('node:url').URL;
  assert.equal(new NodeURL('http://2130706433/').hostname, '127.0.0.1',
    'sanity: this environment\'s URL parser must actually canonicalise integer host forms, or this test proves nothing');
  assert.equal(S.safeHttpUrl('http://2130706433/'), '', 'review_p2_integer_ipv4_rejected');
  assert.equal(S.safeHttpUrl('http://0x7f000001/'), '', 'review_p2_integer_ipv4_rejected');
}
{
  const NodeURL = require('node:url').URL;
  assert.equal(new NodeURL('http://10.0.0x0.0x1/').hostname, '10.0.0.1',
    'sanity: this environment\'s URL parser must actually canonicalise mixed-radix host forms, or this test proves nothing');
  assert.equal(S.safeHttpUrl('http://10.0.0x0.0x1/'), '', 'review_p2_mixed_numeric_ipv4_rejected');
  assert.equal(S.safeHttpUrl('http://10.0.00.01/'), '', 'review_p2_mixed_numeric_ipv4_rejected');
  assert.equal(S.safeHttpUrl('http://0X7F.0X0.0X0.0X1/'), '', 'review_p2_mixed_numeric_ipv4_rejected (uppercase 0X)');
}
// Ordinary DNS-style hostnames remain unaffected.
for (const u of ['https://example.com/', 'https://sub.example.co.uk/', 'https://x0.example.com/'])
  assert.ok(S.safeHttpUrl(u), u);

// PR 4 review finding 5 (P2): snapshot() validated the raw image handle
// against the qsimage-only shape /^image:\/\/qsimage\/\d+\/\d+$/ before the
// image://icon/<name> extraction ever ran, so any image://icon/... handle -
// exactly what `notify-send -i some-icon` produces - failed that check first
// and was thrown away, indistinguishable from no icon at all. The name is
// now pulled out before the qsimage-only check runs.
{
  const iconRow = Store.snapshot({ appName: 'Test', summary: 's', body: 'b', image: 'image://icon/kitty' }, 'n1', { Normal: 1 });
  assert.equal(iconRow.appIcon, 'kitty', 'review_p2_named_icon_hint_preserved');
  assert.equal(iconRow.image, '', 'a named-icon hint is not also a qsimage handle');
}
{
  // The strict appIcon charset (no "/") is what actually keeps a traversal
  // or a foreign scheme from being promoted into a local path lookup, not
  // the extraction itself.
  for (const hostile of ['image://icon/../../etc/passwd', 'image://icon/' + 'a'.repeat(500),
                          'file:///etc/passwd', 'https://example/image.png']) {
    const row = Store.snapshot({ appName: 'Test', summary: 's', body: 'b', image: hostile }, 'n1', { Normal: 1 });
    assert.ok(!row.appIcon.includes('/'), 'review_p2_named_icon_path_traversal_rejected: ' + hostile + ' -> ' + JSON.stringify(row.appIcon));
    assert.equal(row.image, '', hostile);
  }
  const traversal = Store.snapshot({ appName: 'Test', summary: 's', body: 'b', image: 'image://icon/../../etc/passwd' }, 'n1', { Normal: 1 });
  assert.equal(traversal.appIcon, '', 'review_p2_named_icon_path_traversal_rejected');
}
{
  // image://qsimage/<n>/<n> is the separate, already-validated internal
  // handle and must be unaffected by the reordering.
  const qs = Store.snapshot({ appName: 'Test', summary: 's', body: 'b', image: 'image://qsimage/12/1' }, 'n1', { Normal: 1 });
  assert.equal(qs.image, 'image://qsimage/12/1');
  assert.equal(qs.appIcon, '');
}

// PR 4 review finding 6 (P2): the Python persistence allowlist deliberately
// drops link/meeting/phone on write - correctly, so a stored notification
// cannot later assert its own capabilities - but restored() did not
// recompute them, so "Open link"/"Copy number" never came back after a
// restart even for an entirely ordinary notification. restored() now
// re-runs Detect.scan() on the persisted summary/body and lets normalise()
// re-validate the result, rather than persisting the derived fields again.
{
  // A persisted entry as the Python store actually returns one: bounded
  // source text only, no link/meeting/phone - those keys are simply absent.
  const persisted = { key: 'n1', app: 'Chat', summary: 'New message',
    body: 'Join https://meet.google.com/abc-defg-hij or call +44 7911 123456',
    rawBody: 'Join https://meet.google.com/abc-defg-hij or call +44 7911 123456',
    urgency: 1 };
  const row = Store.restored(persisted);
  assert.equal(row.link, 'https://meet.google.com/abc-defg-hij', 'review_p2_restored_link_reconstructed');
  assert.equal(row.meeting, true, 'review_p2_restored_link_reconstructed (meeting link)');
  assert.equal(row.phone, '+44 7911 123456', 'review_p2_restored_phone_reconstructed');
  assert.equal(row.restored, true);
}
{
  // A legacy or tampered on-disk entry carrying a link/phone the current
  // body does not actually support must not have it trusted through
  // restore - it is recomputed from the text, not read off the entry.
  const tampered = { key: 'n1', app: 'Chat', summary: 'New message',
    body: 'Nothing to see here', rawBody: 'Nothing to see here', urgency: 1,
    link: 'https://evil.example/phish', meeting: true, phone: '+1 555 0100' };
  const row = Store.restored(tampered);
  assert.equal(row.link, '', 'review_p2_restored_malicious_link_not_trusted');
  assert.equal(row.meeting, false, 'review_p2_restored_malicious_link_not_trusted');
  assert.equal(row.phone, '', 'review_p2_restored_malicious_link_not_trusted');
}
{
  // A link present in the restored text itself but rejected by today's URL
  // policy (here: a loopback address) must stay unavailable, not merely
  // pass through because Detect found *something* link-shaped.
  const dangerous = { key: 'n1', app: 'Chat', summary: 'New message',
    body: 'See http://127.0.0.1/admin for details',
    rawBody: 'See http://127.0.0.1/admin for details', urgency: 1 };
  const row = Store.restored(dangerous);
  assert.equal(row.link, '', 'review_p2_restored_malicious_link_not_trusted (loopback body link)');
}

// ---------------------------------------------------------------- haseen
// Library values live in another vm realm: compare them as JSON.
const same = (a, b, m) => assert.equal(JSON.stringify(a), JSON.stringify(b), m);
// The disk store's rules (upstream's Python store, now Store.js).
{
  const now = 1_800_000_000;
  const row = Store.snapshot({appName:'Slack', summary:'Sam', body:'hello there'}, 'k1', {Normal:1});
  const code = Store.snapshot({appName:'Bank', summary:'Verification', body:'Your code is 938271'}, 'k2', {Normal:1});
  let live = Store.putLive([], row);
  live = Store.putLive(live, code);
  live = Store.putLive(live, row);                      // replace in place, moves last
  same(live.map(e => e.key), ['k2', 'k1']);
  assert.ok(!JSON.stringify(live).includes('938271'), 'live store never holds a code');
  for (const e of live) for (const k of Object.keys(e)) assert.ok(Store.DISK_FIELDS.includes(k), k);
  assert.equal(Store.putLive(live, {key:'../evil'}).length, 2, 'unsafe keys are refused');
  // Close: an entry moves to history with when and why.
  let history = Store.closeInto([], live[0], 'snoozed', 24, now);
  history = Store.closeInto(history, live[1], 'dismissed', 24, now + 1);
  same(history.map(e => e.closed_reason), ['snoozed', 'dismissed']);
  assert.equal(history[0].summary, 'Verification notification');
  assert.equal(history[0].body, '[redacted]');
  same(Store.newest(history, 10, false).map(e => e.key), ['k1', 'k2']);
  same(Store.newest(history, 10, true).map(e => e.key), ['k2'], 'held = snoozed/silenced only');
  same(Store.forgetHeld(history).map(e => e.key), ['k1']);
  // Retention: 0 keeps nothing; age and the 100-entry cap both bite.
  same(Store.closeInto([], live[1], 'dismissed', 0, now), []);
  assert.equal(Store.retentionHours(5), 24, 'unknown retention falls back to 24');
  assert.equal(Store.trimHistory(history, 1, now + 3601).length, 1, 'one-hour retention drops the older entry');
  let many = [];
  for (let i = 0; i < 130; i++) many = Store.closeInto(many, Object.assign({}, row, {key:'m'+i}), 'expired', 168, now + i);
  assert.equal(many.length, 100);
  assert.equal(many[0].key, 'm30');
  // Files: damage and hostile shapes read as empty, never as trusted data.
  same(Store.parseFile('not json'), []);
  same(Store.parseFile('{"a":1}'), []);
  same(Store.parseFile('[1,"x",null,[]]'), []);
  const tampered = Store.parseFile(JSON.stringify([{key:'t', summary:'Hi', body:'code 482913', link:'javascript:x', replyPath:'/x', bodyRich:'<img src=x>'}]));
  assert.equal(tampered.length, 1);
  assert.ok(!('link' in tampered[0]) && !('replyPath' in tampered[0]) && !('bodyRich' in tampered[0]));
  assert.ok(!JSON.stringify(tampered).includes('482913'), 'codes are re-redacted on read');
  // A restored live row comes back with a short grace (critical waits).
  const back = Store.restored(Store.parseFile(JSON.stringify([Store.forDisk(row)]))[0]);
  assert.equal(back.duration, Store.RESTORE_GRACE);
  assert.equal(back.groupKey, 'app:slack');
}
// Grouping and the deck layout.
{
  const L = load('Layout');
  const rows = [
    {key:'a', groupKey:'app:slack'}, {key:'b', groupKey:'app:mail'}, {key:'c', groupKey:'app:slack'}
  ];
  const h = () => 50;
  const bySource = L.compute(rows, {stacking:'source', expanded:false, gap:6, deckGap:12, heightOf:h});
  same(bySource.decks.map(d => d.key), ['app:slack', 'app:mail']);
  same(bySource.decks[0].rows.map(r => r.key), ['a', 'c']);
  assert.equal(bySource.placements.a.front, true);
  assert.equal(bySource.placements.c.front, false);
  assert.equal(bySource.placements.c.y, L.PEEK, 'collapsed cards peek out by PEEK');
  assert.equal(bySource.height, 50 + L.PEEK + 12 + 50);
  const all = L.compute(rows, {stacking:'all', expanded:false, gap:6, heightOf:h});
  assert.equal(all.decks.length, 1);
  assert.equal(all.placements.a.count, 2, 'the newest of a group wears the count');
  assert.equal(all.placements.c.count, 1);
  const open = L.compute(rows, {stacking:'source', expanded:true, openDeck:'app:slack', gap:6, deckGap:12, heightOf:h});
  assert.equal(open.placements.c.y, 56, 'an open deck lays cards out in full');
  assert.equal(open.placements.b.y, 50 + 6 + 50 + 12);
  assert.equal(L.deckKeyFor(rows[0], 'all'), 'all');
  const leaving = L.compute([rows[0]], {stacking:'all', heightOf:h});
  assert.equal(leaving.placements.a.hidden, false);
}
// Grouping keys: per site for the web, per forwarded app for KDE Connect.
{
  const web = Store.snapshot({appName:'Google Chrome', summary:'Sam', body:'<a href="https://app.slack.com/">app.slack.com</a>hi'}, 'w', {Normal:1});
  assert.equal(web.groupKey, 'web:app.slack.com');
  assert.equal(web.source, 'app.slack.com');
  assert.equal(web.body, 'hi');
  const phone = Store.snapshot({appName:'KDE Connect', summary:'Pixel · WhatsApp', body:'Sam: hi'}, 'p', {Normal:1});
  assert.equal(phone.groupKey, 'kdeconnect:WhatsApp');
  const plain = Store.snapshot({appName:'notify-send', summary:'x', body:'y'}, 'n', {Normal:1});
  assert.equal(plain.groupKey, 'app:notify-send');
}
console.log('security: passed');
