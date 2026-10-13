pragma Singleton

import QtQuick
import "SecurityEvidence.js" as Evidence

// A Security row of the menu hands one page and item to the haseen.security
// panel it opens. Both plugins reach the hand-off here, in qs.Haseen, so the
// menu works when the optional panel's directory is absent. Memory only; the
// panel takes it once, and a closing panel drops one that is left over.
QtObject {
    property var pending: null

    function request(page: string, itemId: string): bool {
        if (!Evidence.member(page, Evidence.pages) || (itemId !== "" && !Evidence.identity(itemId)))
            return false;
        pending = {
            page: page,
            itemId: itemId
        };
        return true;
    }

    function take(): var {
        const route = pending;
        pending = null;
        return route;
    }
}
