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
            const length = end - i;
            if (length === 3 || length === 4)
                return true;
            i = end;
            continue;
        }
        i++;
    }
    return false;
}

function withoutDayName(format) {
    let result = "";
    let quoted = false;
    for (let i = 0; i < format.length;) {
        if (format[i] === "'") {
            if (format[i + 1] === "'") {
                result += "''";
                i += 2;
                continue;
            }
            quoted = !quoted;
            result += format[i++];
            continue;
        }
        if (!quoted && format[i] === "d") {
            let end = i + 1;
            while (format[end] === "d")
                end++;
            const length = end - i;
            if (length === 3 || length === 4) {
                i = end;
                while (i < format.length && /[\s,·|/–—-]/.test(format[i]))
                    i++;
                continue;
            }
        }
        result += format[i++];
    }
    return result.replace(/[\s,·|/–—-]+$/, "");
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
