#!/usr/bin/env python3
"""tools/fonts.py - one font and one type scale in haseen's own QML (plan 141).

  tools/fonts.py check            every rule below holds; prints each breach
  tools/fonts.py --root DIR check the same over another checkout (the tests')

Scope: share/haseen/shell/*.qml, Haseen/ (but Theme.qml, which defines the
tokens), plugins/ and templates/.
Compat/ is excluded: it implements Omarchy's and DMS's own components, whose
sizes are their Style tokens (already haseen's scale, plan 115). greeter/ is
excluded: it runs as the greeter user and cannot read the user's font.

Rules:
  1. A text element (Text, TextInput, TextField, TextEdit, TextArea,
     TextMetrics, FontMetrics, Label) sets its own family and pixel size, or
     copies a whole font (`font: other.font`). The shell sets no application
     font, so an element without a family falls back to the system sans.
  2. A family is the theme's: Theme.fontFamily, Theme.fontMono or
     Theme.font.{family,resolvedFamily,menuFamily}, or a property holding one.
  3. A pixel size is a Theme.font token (caption, bodySmall, body, subtitle,
     title, heading, display, displayLarge, iconSmall, icon, iconLarge) or
     Theme.barMetrics.iconFont, or a property holding one. A condition may
     choose between them (`vertical ? Theme.font.caption : Theme.font.body`);
     arithmetic, Math.* and Theme.fontSize may not make one up.
  4. font.pointSize is never used.
  5. An assignment in JavaScript (`label.font.pixelSize = …`, or `??=`)
     follows 2 to 4; an arithmetic one (`+=`, `++`) is never a token.

Strings, comments and regex literals are masked first, so a brace, colon or
quote inside them changes nothing. A string may span lines; a quote that no
other closes before the end of the file ends at its line.

A line, or the line above it, marked `// fonts-ignore: <why>` is exempt: the
lock and the screensaver are full-screen and scale with it, and Arabic script
needs a font that has it. A property marked at its definition exempts every
use of it.
"""

import os
import re
import sys

ROOT = SHELL = ""


def set_root(root):
    global ROOT, SHELL
    ROOT = os.path.normpath(root)
    SHELL = os.path.join(ROOT, "share", "haseen", "shell")


set_root(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

TEXT_TYPES = ("Text", "TextInput", "TextField", "TextEdit", "TextArea", "TextMetrics", "FontMetrics", "Label")
FAMILY_TOKENS = {"Theme.fontFamily", "Theme.fontMono", "Theme.font.family", "Theme.font.resolvedFamily",
                 "Theme.font.menuFamily"}
SIZE_TOKENS = {"Theme.font." + t for t in ("caption", "bodySmall", "body", "subtitle", "title", "heading",
                                            "display", "displayLarge", "iconSmall", "icon", "iconLarge")}
SIZE_TOKENS.add("Theme.barMetrics.iconFont")
IGNORE = "fonts-ignore:"
ELEMENT = re.compile(r"(?<![\w.])(?:\w+\.)?(" + "|".join(TEXT_TYPES) + r")\s*\{")
REF = re.compile(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$")
ASSIGN = re.compile(r"(?<![\w.])font\.(family|pixelSize)\s*:(?!:)")
# An assignment in JavaScript, `label.font.pixelSize = …`. An arithmetic one
# (+=, ++) is relative to a size and never a token; a logical one (??=)
# assigns its value or keeps one already checked.
IMPERATIVE = re.compile(r"(?<![\w$])font\.(family|pixelSize|pointSize)\s*(?P<op>\+\+|--|[-+*/]=|(?:\|\||&&|\?\?)?=(?!=))")
RELATIVE = {"++", "--", "+=", "-=", "*=", "/="}
PROPERTY = re.compile(r"\b(?:readonly\s+)?(?:required\s+)?property\s+\w+\s+(\w+)\s*:")


def rel(path):
    return os.path.relpath(path, ROOT)


def files():
    out = [os.path.join(SHELL, f) for f in sorted(os.listdir(SHELL)) if f.endswith(".qml")]
    # The qs.Haseen singletons (MenuMetrics) hold sizes the plugins read;
    # Theme.qml defines the tokens themselves.
    haseen = os.path.join(SHELL, "Haseen")
    if os.path.isdir(haseen):
        out += [os.path.join(haseen, f) for f in sorted(os.listdir(haseen)) if f.endswith(".qml") and f != "Theme.qml"]
    for sub in ("Haseen/Widgets", "plugins", "templates"):
        base = os.path.join(SHELL, sub)
        for dirpath, dirnames, names in os.walk(base):
            dirnames.sort()
            out += [os.path.join(dirpath, n) for n in sorted(names) if n.endswith(".qml")]
    return out


# A "/" after one of these, or after one of the keywords, starts a regex
# literal; after anything else (a name, a number, ")" or "]") it divides.
REGEX_AFTER = set("(,=:[!&|?{};+-*%<>~^")
REGEX_KEYWORDS = {"return", "typeof", "case", "in", "of", "delete", "void", "throw", "new", "else", "do", "yield", "await"}


def regex_starts(out, i):
    """Whether the "/" at i opens a regex literal, from what precedes it."""
    k = i - 1
    while k >= 0 and out[k] in " \t\r\n":
        k -= 1
    if k < 0 or out[k] in REGEX_AFTER:
        return True
    j = k
    while j >= 0 and (out[j].isalnum() or out[j] in "_$"):
        j -= 1
    return "".join(out[j + 1:k + 1]) in REGEX_KEYWORDS


def mask(text):
    """The text with comments blanked and the contents of strings and regex
    literals replaced, so braces, colons and quotes inside them do not count;
    offsets and newlines stay the same. A QML string may span lines; a quote
    with no closing one before the end of the file is not a string and ends
    at its line, so one stray quote cannot hide the rest of a file."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out[i:j] = " " * (j - i)
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out[i:j] = [ch if ch == "\n" else " " for ch in text[i:j]]
            i = j
        elif c == "/" and regex_starts(out, i):
            j, in_class = i + 1, False
            while j < n and text[j] != "\n":
                if text[j] == "\\":
                    # A regex cannot hold a newline, escaped or not.
                    if j + 1 < n and text[j + 1] == "\n":
                        break
                    j += 2
                    continue
                if text[j] == "[":
                    in_class = True
                elif text[j] == "]":
                    in_class = False
                elif text[j] == "/" and not in_class:
                    break
                j += 1
            if j < n and text[j] == "/":
                out[i + 1:j] = "_" * (j - i - 1)
                i = j + 1
            else:
                i += 1
        elif c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            if j >= n and c != "`":
                j = text.find("\n", i)
                j = n if j < 0 else j
            j = min(j, n)
            out[i + 1:j] = [ch if ch == "\n" else "_" for ch in text[i + 1:j]]
            i = j + 1 if j < n and text[j] == c else j
        else:
            i += 1
    return "".join(out)


def close_of(masked, start):
    """Index of the brace matching the one at `start`."""
    depth = 0
    for i in range(start, len(masked)):
        if masked[i] == "{":
            depth += 1
        elif masked[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(masked) - 1


def expression(text, masked, i):
    """The expression starting at i: to the end of the statement, across
    lines while brackets are open or a line ends in an operator."""
    depth, j, n = 0, i, len(masked)
    while j < n:
        c = masked[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and c == ";":
            break
        elif depth == 0 and c == "\n":
            line = masked[i:j].rstrip()
            rest = masked[j + 1:].lstrip()
            if not (line.endswith(("?", ":", "&&", "||", "+", "-", "*", "/", ",", "("))
                    or rest.startswith(("?", ":", "&&", "||", "."))):
                break
        j += 1
    return text[i:j].strip(), masked[i:j]


def split_ternary(expr):
    """cond ? a : b at the top level, else None."""
    depth, q = 0, -1
    for k, c in enumerate(expr):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth == 0 and c == "?" and q < 0:
            q = k
        elif depth == 0 and c == ":" and q >= 0:
            nested = expr[q + 1:k].count("?") - expr[q + 1:k].count(":")
            if nested <= 0:
                return expr[:q], expr[q + 1:k], expr[k + 1:]
    return None


def leaves(expr):
    expr = expr.strip()
    while expr.startswith("(") and expr.endswith(")") and close_paren(expr) == len(expr) - 1:
        expr = expr[1:-1].strip()
    t = split_ternary(expr)
    if t:
        return leaves(t[1]) + leaves(t[2])
    return [expr]


def close_paren(expr):
    depth = 0
    for k, c in enumerate(expr):
        depth += c == "("
        depth -= c == ")"
        if depth == 0:
            return k
    return -1


class Checker:
    def __init__(self):
        self.problems = []
        self.sources = {}
        self.definitions = {}  # name -> [(path, line, expr)]
        self.assignments = {}  # name -> [(path, line, expr)]

    def load(self):
        for path in files():
            with open(path, encoding="utf-8") as f:
                text = f.read()
            masked = mask(text)
            self.sources[path] = (text, masked)
            for m in PROPERTY.finditer(masked):
                expr, _ = expression(text, masked, m.end())
                self.definitions.setdefault(m.group(1), []).append((path, self.line(text, m.start()), expr))
            for m in re.finditer(r"(?m)^\s*(\w+)\s*:(?!:)", masked):
                expr, _ = expression(text, masked, m.end())
                self.assignments.setdefault(m.group(1), []).append((path, self.line(text, m.start()), expr))

    @staticmethod
    def line(text, offset):
        return text.count("\n", 0, offset) + 1

    def ignored(self, path, line):
        lines = self.sources[path][0].split("\n")
        here = lines[line - 1] if line - 1 < len(lines) else ""
        above = lines[line - 2] if line >= 2 else ""
        return IGNORE in here or IGNORE in above

    def report(self, path, line, why):
        if not self.ignored(path, line):
            self.problems.append((rel(path), line, why))

    def related(self, path, name, owner=None):
        """Definitions and assignments of `name` a reference from `path` can
        reach: the file of the singleton or component it names (`owner`, as
        in MenuMetrics.iconSize), else the same file, else the same
        directory, else anywhere."""
        found = []
        for table in (self.definitions, self.assignments):
            found += table.get(name, [])
        if owner:
            named = [d for d in found if os.path.basename(d[0]) == owner + ".qml"]
            if named:
                return named
        for scope in (lambda p: p == path, lambda p: os.path.dirname(p) == os.path.dirname(path)):
            near = [d for d in found if scope(d[0])]
            if near:
                return near
        return [d for d in self.definitions.get(name, [])]

    def valid(self, expr, path, tokens, kind, seen):
        for leaf in leaves(expr):
            if leaf in tokens:
                continue
            if not REF.match(leaf) or leaf.startswith("Theme."):
                return f"{kind} {leaf!r} is not a theme token"
            parts = leaf.split(".")
            name = parts[-1]
            owner = parts[-2] if len(parts) > 1 and parts[-2][:1].isupper() else None
            if (path, name) in seen:
                continue
            seen.add((path, name))
            defs = [d for d in self.related(path, name, owner) if d[2] != leaf]
            if not defs:
                return f"{kind} {leaf!r} does not resolve to a theme token"
            for dpath, dline, dexpr in defs:
                why = self.valid(dexpr, dpath, tokens, kind, seen)
                if why and not self.ignored(dpath, dline):
                    return f"{why} (via {name} at {rel(dpath)}:{dline})"
        return None

    def check(self):
        for path, (text, masked) in self.sources.items():
            for m in re.finditer(r"\bfont\.pointSize\s*:", masked):
                self.report(path, self.line(text, m.start()), "font.pointSize; use a Theme.font pixel size")
            # Every assignment, whatever the element: a component built on
            # Text (Glyph) takes its size where it is used.
            for m in ASSIGN.finditer(masked):
                expr, _ = expression(text, masked, m.end())
                self.value(path, self.line(text, m.start()), m.group(1), expr)
            for m in IMPERATIVE.finditer(masked):
                line = self.line(text, m.start())
                if m.group(1) == "pointSize":
                    self.report(path, line, "font.pointSize; use a Theme.font pixel size")
                elif m.group("op") in RELATIVE:
                    self.report(path, line, f"font.{m.group(1)} {m.group('op')} is relative; assign a theme token")
                else:
                    expr, _ = expression(text, masked, m.end())
                    self.value(path, line, m.group(1), expr)
            for m in ELEMENT.finditer(masked):
                open_at = m.end() - 1
                self.element(path, text, masked, m.group(1), open_at, close_of(masked, open_at))
        return [f"{path}:{line}: {why}" for path, line, why in sorted(set(self.problems))]

    def value(self, path, line, which, expr):
        tokens, kind = (FAMILY_TOKENS, "family") if which == "family" else (SIZE_TOKENS, "size")
        why = self.valid(expr, path, tokens, kind, set())
        if why:
            self.report(path, line, why)

    def element(self, path, text, masked, kind, open_at, close_at):
        # A component of the same name next to this file (haseen.security's
        # Label.qml) is not Qt's type; its own file is checked instead.
        if os.path.exists(os.path.join(os.path.dirname(path), kind + ".qml")):
            return
        family = size = whole = None
        depth, i = 0, open_at + 1
        while i < close_at:
            c = masked[i]
            if c == "{":
                # The grouped form: font { family: …; pixelSize: … }
                if depth == 0 and re.search(r"(?<![\w.])font\s*$", masked[open_at + 1:i]):
                    end = close_of(masked, i)
                    family, size = self.group(path, text, masked, i, end, family, size)
                    i = end + 1
                    continue
                depth += 1
            elif c == "}":
                depth -= 1
            elif depth == 0:
                m = re.compile(r"(?<![\w.])font(\.(family|pixelSize))?\s*:(?!:)").match(masked, i)
                if m:
                    expr, _ = expression(text, masked, m.end())
                    where = (expr, self.line(text, m.start()))
                    if m.group(2) == "family":
                        family = where
                    elif m.group(2) == "pixelSize":
                        size = where
                    else:
                        whole = where
                    i = m.end()
                    continue
            i += 1
        line = self.line(text, open_at)
        if whole:
            if not re.match(r"^[A-Za-z_][\w.]*\.font$", whole[0]):
                self.report(path, whole[1], f"font: {whole[0]!r} is not another element's font")
            return
        if not family:
            self.report(path, line, f"{kind} has no font.family (the shell has no default font)")
        if not size:
            self.report(path, line, f"{kind} has no font.pixelSize")

    def group(self, path, text, masked, open_at, close_at, family, size):
        for m in re.finditer(r"(?<![\w.])(family|pixelSize)\s*:", masked[open_at:close_at]):
            at = open_at + m.end()
            expr, _ = expression(text, masked, at)
            where = (expr, self.line(text, at))
            self.value(path, where[1], m.group(1), expr)
            if m.group(1) == "family":
                family = where
            else:
                size = where
        return family, size


def main(argv):
    if len(argv) == 4 and argv[1] == "--root":
        set_root(argv[2])
        argv = [argv[0], argv[3]]
    if len(argv) != 2 or argv[1] != "check":
        print(__doc__.strip().split("\n\n")[0], file=sys.stderr)
        return 2
    checker = Checker()
    checker.load()
    problems = checker.check()
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        print(f"fonts: {len(problems)} problem(s); see plan 141", file=sys.stderr)
        return 1
    print(f"fonts: {len(checker.sources)} files, one family, one scale")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
