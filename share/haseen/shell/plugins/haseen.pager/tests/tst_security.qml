import QtQuick
import QtTest
import "../Security.js" as Security
import "../Markup.js" as Markup
import "../Store.js" as Store
import "../Layout.js" as Layout

// The same policy code under Qt's own JS engine (qmltestrunner), where it
// actually runs. From omapager's tests/tst_security.qml
// (https://github.com/njpatel/omapager, MIT, Copyright (c) 2026 Neil Jagdish
// Patel), plus the haseen disk-store rules.
TestCase {
    name: "SecurityPolicy"

    function test_urls() {
        compare(Security.safeHttpUrl("https://paypal.com@evil.example"), "");
        compare(Security.safeHttpUrl("https://example.com/%250a"), "");
        compare(Security.safeHttpUrl("http://127.0x/"), "");
        compare(Security.safeHttpUrl("https://EXAMPLE.com"), "https://example.com/");
        compare(Security.safeMailtoUrl("mailto:a@example.com?attach=/etc/passwd"), "");
    }

    function test_markup_and_storage() {
        verify(Markup.render('<img src="file:///etc/passwd">').indexOf('<img') < 0);
        const row = Store.snapshot({
            appName: "Test",
            summary: "Verification",
            body: "Your code is 938271"
        }, "n1", {
            Normal: 1
        });
        compare(row.code, "938271");
        verify(JSON.stringify(Store.sanitiseForPersistence(row)).indexOf("938271") < 0);
        verify(JSON.stringify(Store.forDisk(row)).indexOf("938271") < 0);
    }

    function test_disk_store() {
        const row = Store.snapshot({
            appName: "Slack",
            summary: "Sam",
            body: "hello"
        }, "k1", {
            Normal: 1
        });
        let history = Store.closeInto([], row, "silenced", 24, 1000);
        compare(history.length, 1);
        compare(Store.newest(history, 5, true).length, 1);
        compare(Store.forgetHeld(history).length, 0);
        compare(Store.closeInto([], row, "dismissed", 0, 1000).length, 0);
        compare(Store.parseFile("{").length, 0);
    }

    function test_layout() {
        const out = Layout.compute([
            {
                key: "a",
                groupKey: "app:x"
            },
            {
                key: "b",
                groupKey: "app:x"
            }
        ], {
            stacking: "source",
            expanded: false,
            heightOf: () => 50
        });
        compare(out.decks.length, 1);
        compare(out.placements.b.y, Layout.PEEK);
    }
}
