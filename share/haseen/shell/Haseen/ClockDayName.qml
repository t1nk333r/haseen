pragma Singleton

import QtQuick
import "ClockDayName.js" as Format

QtObject {
    function hasDayName(format: string): bool {
        return Format.hasDayName(format);
    }

    function effectiveFormat(format: string, showDayName: var, vertical: bool): string {
        return Format.effectiveFormat(format, showDayName, vertical);
    }

    function isShown(format: string, showDayName: var): bool {
        return Format.isShown(format, showDayName);
    }
}
