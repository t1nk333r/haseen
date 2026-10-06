.pragma library

// The launcher's calculator: `=` then an expression. A small recursive-descent
// parser, not eval(): the input is typed by the user but runs inside the shell,
// so nothing but arithmetic may ever be executed.
//
//   numbers      12  3.5  .5  1e3  1_000 (underscores ignored)  0x1f
//   operators    + - * / % ^ (power, right-associative)  ! (factorial)
//                x and × for *, ÷ for /, unary + and -
//   grouping     ( )
//   constants    pi π e tau
//   functions    sqrt cbrt abs round floor ceil sin cos tan asin acos atan
//                ln log (base 10) log2 exp min max
//   percent      50% → 0.5 ; 200 + 10% → 220 (as most calculators do)
//
// evaluate(text) -> {ok: true, value} or {ok: false, error}.

const CONSTANTS = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI };
const FUNCTIONS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round,
    floor: Math.floor, ceil: Math.ceil, sin: Math.sin, cos: Math.cos,
    tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
    ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp,
    min: Math.min, max: Math.max
};

function tokenize(text) {
    const tokens = [];
    const s = String(text).replace(/×/g, "*").replace(/÷/g, "/");
    let i = 0;
    while (i < s.length) {
        const c = s[i];
        if (/\s/.test(c)) {
            i++;
            continue;
        }
        const hex = /^0x[0-9a-fA-F]+/.exec(s.slice(i));
        if (hex) {
            tokens.push({ type: "num", value: parseInt(hex[0], 16) });
            i += hex[0].length;
            continue;
        }
        const num = /^(\d[\d_]*\.?[\d_]*|\.\d[\d_]*)([eE][+-]?\d+)?/.exec(s.slice(i));
        if (num) {
            tokens.push({ type: "num", value: parseFloat(num[0].replace(/_/g, "")) });
            i += num[0].length;
            continue;
        }
        // "x" right after a number or ")" and before a number or "(" is
        // multiplication ("3x4"); anywhere else it is a letter ("max", "exp").
        const prev = tokens[tokens.length - 1];
        if (c === "x" && prev && (prev.type === "num" || (prev.type === "op" && prev.value === ")")) && /^\s*[\d(.]/.test(s.slice(i + 1))) {
            tokens.push({ type: "op", value: "*" });
            i++;
            continue;
        }
        const word = /^[A-Za-zπ][A-Za-z0-9]*/.exec(s.slice(i));
        if (word) {
            tokens.push({ type: "word", value: word[0].toLowerCase() === "π" ? "π" : word[0].toLowerCase() });
            i += word[0].length;
            continue;
        }
        if ("+-*/%^!(),".indexOf(c) >= 0) {
            tokens.push({ type: "op", value: c });
            i++;
            continue;
        }
        throw new Error("unexpected '" + c + "'");
    }
    return tokens;
}

function Parser(tokens) {
    this.tokens = tokens;
    this.pos = 0;
}

Parser.prototype.peek = function () {
    return this.tokens[this.pos];
};

Parser.prototype.take = function (value) {
    const t = this.tokens[this.pos];
    if (t && t.type === "op" && t.value === value) {
        this.pos++;
        return true;
    }
    return false;
};

// expr := term (('+' | '-') term)*
Parser.prototype.expr = function () {
    let left = this.term();
    for (;;) {
        if (this.take("+"))
            left = this.addend(left, 1);
        else if (this.take("-"))
            left = this.addend(left, -1);
        else
            return left;
    }
};

// `200 + 10%` is 220: a percentage right after + or - is a share of the left.
Parser.prototype.addend = function (left, sign) {
    const right = this.term();
    return { value: left.value + sign * (right.percent ? left.value * right.value : right.value), percent: false };
};

// term := unary (('*' | '/' | '%'-as-modulo) unary)*
Parser.prototype.term = function () {
    let left = this.unary();
    for (;;) {
        if (this.take("*"))
            left = { value: left.value * this.unary().value, percent: false };
        else if (this.take("/"))
            left = { value: left.value / this.unary().value, percent: false };
        else if (this.isModulo())
            left = { value: left.value % this.unary().value, percent: false };
        else
            return left;
    }
};

// `%` followed by an operand is modulo; otherwise it marks a percentage.
Parser.prototype.isModulo = function () {
    const t = this.peek();
    const next = this.tokens[this.pos + 1];
    if (!t || t.type !== "op" || t.value !== "%" || !next)
        return false;
    if (next.type === "num" || next.type === "word" || (next.type === "op" && (next.value === "(" || next.value === "-"))) {
        this.pos++;
        return true;
    }
    return false;
};

Parser.prototype.unary = function () {
    if (this.take("-")) {
        const v = this.unary();
        return { value: -v.value, percent: v.percent };
    }
    if (this.take("+"))
        return this.unary();
    return this.power();
};

// power := postfix ('^' unary)?   (right-associative: 2^3^2 = 2^9)
Parser.prototype.power = function () {
    const base = this.postfix();
    if (this.take("^")) {
        const exponent = this.unary();
        return { value: Math.pow(base.value, exponent.value), percent: false };
    }
    return base;
};

Parser.prototype.postfix = function () {
    let v = this.primary();
    for (;;) {
        if (this.take("!")) {
            v = { value: factorial(v.value), percent: false };
        } else if (this.peekPercent()) {
            this.pos++;
            v = { value: v.value / 100, percent: true };
        } else {
            return v;
        }
    }
};

Parser.prototype.peekPercent = function () {
    const t = this.peek();
    if (!t || t.type !== "op" || t.value !== "%")
        return false;
    const next = this.tokens[this.pos + 1];
    return !next || (next.type === "op" && next.value !== "(" && next.value !== "-");
};

Parser.prototype.primary = function () {
    const t = this.peek();
    if (!t)
        throw new Error("expression ends early");
    if (t.type === "num") {
        this.pos++;
        return { value: t.value, percent: false };
    }
    if (t.type === "op" && t.value === "(") {
        this.pos++;
        const v = this.expr();
        if (!this.take(")"))
            throw new Error("missing )");
        return { value: v.value, percent: false };
    }
    if (t.type === "word") {
        this.pos++;
        if (Object.prototype.hasOwnProperty.call(CONSTANTS, t.value))
            return { value: CONSTANTS[t.value], percent: false };
        if (Object.prototype.hasOwnProperty.call(FUNCTIONS, t.value)) {
            if (!this.take("("))
                throw new Error(t.value + " needs (");
            const args = [this.expr().value];
            while (this.take(","))
                args.push(this.expr().value);
            if (!this.take(")"))
                throw new Error("missing )");
            return { value: FUNCTIONS[t.value].apply(null, args), percent: false };
        }
        throw new Error("unknown '" + t.value + "'");
    }
    throw new Error("unexpected '" + t.value + "'");
};

function factorial(n) {
    if (n < 0 || n !== Math.floor(n))
        throw new Error("factorial needs a whole number");
    if (n > 170)
        return Infinity;
    let r = 1;
    for (let i = 2; i <= n; i++)
        r *= i;
    return r;
}

function evaluate(text) {
    try {
        const tokens = tokenize(text);
        if (tokens.length === 0)
            return { ok: false, error: "" };
        const p = new Parser(tokens);
        const v = p.expr();
        if (p.pos !== tokens.length)
            throw new Error("unexpected '" + tokens[p.pos].value + "'");
        const value = v.value;
        if (typeof value !== "number" || Number.isNaN(value))
            throw new Error("not a number");
        return { ok: true, value: value };
    } catch (e) {
        return { ok: false, error: String(e.message || e) };
    }
}

// The shown result: integers as integers, otherwise up to 12 significant
// digits without trailing zeros; the infinities in words.
function format(value) {
    if (value === Infinity)
        return "∞";
    if (value === -Infinity)
        return "−∞";
    if (Number.isInteger(value) && Math.abs(value) < 1e21)
        return String(value);
    const s = Number(value.toPrecision(12));
    return String(s);
}
