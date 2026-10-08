.pragma library

function hasDayName(format) {
    let quoted = false;
    for (let i = 0; i < format.length;) {
        if (format[i] === "'") {
            if (format[i + 1] === "'") {
                i += 2;
                continue;
            }
            quoted = !quoted;
            i++;
            continue;
        }
        if (!quoted && format[i] === "d") {
            let end = i + 1;
            while (format[end] === "d")
                end++;
            if (end - i >= 3)
                return true;
            i = end;
            continue;
        }
        i++;
    }
    return false;
}
function _isSeparator(character) {
    return /[\s,،·|/–—-]/.test(character);
}

function withoutDayName(format) {
    let result = "";
    let quoted = false;
    let trailingSeparatorStart = -1;
    for (let i = 0; i < format.length;) {
        if (format[i] === "'") {
            if (format[i + 1] === "'") {
                result += "''";
                i += 2;
                trailingSeparatorStart = -1;
                continue;
            }
            quoted = !quoted;
            result += format[i++];
            trailingSeparatorStart = -1;
            continue;
        }
        if (quoted) {
            result += format[i++];
            trailingSeparatorStart = -1;
            continue;
        }
        if (format[i] === "d") {
            let end = i + 1;
            while (format[end] === "d")
                end++;
            const length = end - i;
            if (length < 3) {
                result += format.slice(i, end);
                i = end;
                trailingSeparatorStart = -1;
                continue;
            }
            const numericLength = length % 4;
            if (numericLength === 1 || numericLength === 2) {
                result += format.slice(end - numericLength, end);
                i = end;
                trailingSeparatorStart = -1;
                continue;
            }
            i = end;
            let after = i;
            while (after < format.length && _isSeparator(format[after]))
                after++;
            if (after > i) {
                i = after;
                continue;
            }
            if (trailingSeparatorStart >= 0) {
                result = result.slice(0, trailingSeparatorStart);
                trailingSeparatorStart = -1;
            }
            continue;
        }
        const character = format[i++];
        if (_isSeparator(character)) {
            if (trailingSeparatorStart < 0)
                trailingSeparatorStart = result.length;
            result += character;
        } else {
            result += character;
            trailingSeparatorStart = -1;
        }
    }
    return result;
}

function effectiveFormat(format, showDayName, vertical) {
    if (typeof showDayName !== "boolean")
        return format;
    if (!showDayName)
        return withoutDayName(format);
    if (hasDayName(format))
        return format;
    return vertical ? "dddd\n" + format : "dddd " + format;
}

function isShown(format, showDayName) {
    return typeof showDayName === "boolean" ? showDayName : hasDayName(format);
}
