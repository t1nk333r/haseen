#!/usr/bin/env python3
"""tools/i18n.py - haseen's interface catalogs (plan 109).

  tools/i18n.py extract      rewrite the English source catalogs
                             (share/haseen/i18n/en/{shell,menu,notify}.json)
                             from the code
  tools/i18n.py check        the catalogs are fresh, every translation is
                             complete and keeps its placeholders, no QML text
                             property holds bare English
  tools/i18n.py stats        per language: strings, translated, reviewed
  tools/i18n.py --root DIR … the same over another checkout (the tests' own)

Strings are keyed by their English (docs/architecture.md, "Interface
language"). Where English is found:
  shell   share/haseen/shell/**/*.{qml,js} outside Compat/, greeter/ and
          templates/: I18n.tr("…"), I18n.tn("…", "…", n), I18n.mark("…")
          and, in JS helpers, N_("…") and N_n("…", "…"); the category
          labels of share/haseen/default/catalog.json (the menu's Install
          and Remove); the descriptions and `-- Section ---` names of the
          binds in share/haseen/default/hypr/*.lua (the keybind sheet)
  menu    share/haseen/default/menu.jsonc: each id's label, title and
          description
  notify  bash (bin/, share/haseen/{lib,omarchy,layers}, plugin scripts):
          i18n "…" and i18n_n "…" "…" N (share/haseen/lib/i18n.sh)
Only literal strings count: a call on a variable is translated at run time
but not collected, so the English it carries must be marked where it is
written.
"""

import json
import os
import re
import sys

ROOT = SHARE = SHELL = I18N = MENU = APP_CATALOG = HYPR = ""


def set_root(root):
    """The checkout to read; --root DIR points the tool at another tree."""
    global ROOT, SHARE, SHELL, I18N, MENU, APP_CATALOG, HYPR
    ROOT = os.path.normpath(root)
    SHARE = os.path.join(ROOT, "share", "haseen")
    SHELL = os.path.join(SHARE, "shell")
    I18N = os.path.join(SHARE, "i18n")
    MENU = os.path.join(SHARE, "default", "menu.jsonc")
    APP_CATALOG = os.path.join(SHARE, "default", "catalog.json")
    HYPR = os.path.join(SHARE, "default", "hypr")


set_root(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SHELL_SKIP = ("Compat", "greeter", "templates", "Common", "Commons", "Ui", "Widgets", "Services", "Modules")
CATALOGS = ("shell", "menu", "notify")
PLURAL_FORMS = {"en": ["one", "other"], "ar": ["zero", "one", "two", "few", "many", "other"]}
PLACEHOLDER = re.compile(r"%[1-9]")

# A QML text property assigned bare English: `text: "Cancel"`, also inline
# (`Text { text: "Cancel" }`) and in a model's object literal. The check
# fails on it unless the line says `// i18n-ignore` (a product name, a
# sample, a machine value shown as is). Only a value with a capital or a
# space counts, so a lower-case machine word ("auto") passes.
TEXT_PROPS = (
    "text|label|title|subtitle|placeholderText|description|hint|tooltip|toolTip|"
    "message|heading|caption|emptyText|summary|body|confirmText|cancelText"
)
BARE_TEXT = re.compile(r'(?<![\w.$])(?:%s)\s*:\s*(["\'])((?:\\.|(?!\1).)*)\1(?=\s*(?:$|[,;}\]]|//))' % TEXT_PROPS)


class Failure(Exception):
    pass


def rel(path):
    return os.path.relpath(path, ROOT)


# --- string literals --------------------------------------------------------

JS_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


def js_literal(text, i):
    """The JS string literal starting at text[i] (a quote) -> (value, end)."""
    quote = text[i]
    out = []
    j = i + 1
    while j < len(text):
        c = text[j]
        if c == quote:
            return "".join(out), j + 1
        if c == "\n":
            break
        if c == "\\":
            j += 1
            e = text[j]
            if e == "u":
                if text[j + 1] == "{":
                    k = text.index("}", j)
                    out.append(chr(int(text[j + 2:k], 16)))
                    j = k + 1
                    continue
                out.append(chr(int(text[j + 1:j + 5], 16)))
                j += 5
                continue
            if e == "x":
                out.append(chr(int(text[j + 1:j + 3], 16)))
                j += 3
                continue
            out.append(JS_ESCAPES.get(e, e))
            j += 1
            continue
        out.append(c)
        j += 1
    raise Failure("unterminated string")


def skip_space(text, i):
    while i < len(text) and text[i] in " \t\r\n":
        i += 1
    return i


def strip_comment_lines(text):
    """Blank whole-line // comments and /* */ blocks, keeping line numbers:
    a comment's example call is not a string to translate. Trailing comments
    stay; a regex literal holding a quote would derail a full lexer."""
    out = []
    in_block = False
    for line in text.split("\n"):
        stripped = line.lstrip()
        if in_block:
            if "*/" in line:
                in_block = False
            out.append("")
        elif stripped.startswith("//"):
            out.append("")
        elif stripped.startswith("/*"):
            in_block = "*/" not in stripped[2:]
            out.append("")
        else:
            out.append(line)
    return "\n".join(out)


def js_calls(text, name, arity):
    """Every NAME(literal[, literal…]) in text: (line, [values])."""
    found = []
    pattern = re.compile(r"(?<![\w.$])" + re.escape(name) + r"\s*\(")
    for m in pattern.finditer(text):
        i = skip_space(text, m.end())
        values = []
        ok = True
        for k in range(arity):
            if i >= len(text) or text[i] not in "\"'":
                ok = False
                if text[i:i + 1] == "`":
                    raise Failure("%s: line %d: a template literal cannot be collected" % (name, text.count("\n", 0, i) + 1))
                break
            value, i = js_literal(text, i)
            # "a" + "b" is not collected: write one literal.
            i = skip_space(text, i)
            if text[i:i + 1] == "+":
                raise Failure("%s: line %d: a concatenated literal cannot be collected" % (name, text.count("\n", 0, i) + 1))
            values.append(value)
            if k < arity - 1:
                if text[i:i + 1] != ",":
                    ok = False
                    break
                i = skip_space(text, i + 1)
        if ok:
            found.append((text.count("\n", 0, m.start()) + 1, values))
    return found


def bash_calls(text, name, arity):
    """Every `NAME 'lit' "lit"` in bash; double-quoted literals may not expand."""
    found = []
    pattern = re.compile(r"(?<![\w-])" + re.escape(name) + r"[ \t]+")
    for m in pattern.finditer(text):
        i = m.end()
        values = []
        for _ in range(arity):
            if i >= len(text) or text[i] not in "\"'":
                values = None
                break
            quote = text[i]
            j = i + 1
            out = []
            while j < len(text) and text[j] != quote:
                c = text[j]
                if quote == '"' and c == "\\" and text[j + 1] in '"\\$`':
                    out.append(text[j + 1])
                    j += 2
                    continue
                if quote == '"' and c in "$`":
                    raise Failure("%s: line %d: a translated string may not expand ($ or `); pass it as %%1" % (name, text.count("\n", 0, i) + 1))
                out.append(c)
                j += 1
            values.append("".join(out))
            i = j + 1
            while i < len(text) and text[i] in " \t":
                i += 1
        if values:
            found.append((text.count("\n", 0, m.start()) + 1, values))
    return found


# --- sources ----------------------------------------------------------------

def shell_files():
    for base, dirs, files in os.walk(SHELL):
        parts = os.path.relpath(base, SHELL).split(os.sep)
        if parts[0] in SHELL_SKIP or "tests" in parts:
            dirs[:] = []
            continue
        dirs.sort()
        for f in sorted(files):
            if f.endswith((".qml", ".js")):
                yield os.path.join(base, f)


def add(catalog, origins, key, value, where):
    if not key.strip():
        raise Failure("%s: an empty string is marked for translation" % where)
    old = catalog.get(key)
    if old is not None and old != value:
        if isinstance(old, dict) or isinstance(value, dict):
            raise Failure("%s: %r is both a plain and a counted string (first at %s)" % (where, key, origins[key]))
    catalog[key] = value
    origins.setdefault(key, where)


def collect_shell():
    catalog, origins = {}, {}
    for path in shell_files():
        text = strip_comment_lines(open(path, encoding="utf-8").read())
        where = rel(path)
        try:
            for line, (s,) in js_calls(text, "I18n.tr", 1) + js_calls(text, "I18n.mark", 1) + js_calls(text, "N_", 1):
                add(catalog, origins, s, s, "%s:%d" % (where, line))
            for line, (one, other) in js_calls(text, "I18n.tn", 2) + js_calls(text, "N_n", 2):
                add(catalog, origins, other, {"one": one, "other": other}, "%s:%d" % (where, line))
        except Failure as e:
            raise Failure("%s: %s" % (where, e))
    collect_extra(catalog, origins)
    return catalog, origins


# b("KEYS", "Description", …) or haseen.bind(…): one literal description,
# not one built with `..` (the workspace binds number theirs).
LUA_BIND = re.compile(r'(?:^|[^\w.])(?:b|haseen\.bind|haseen\.rebind)\(\s*"[^"\n]*"\s*,\s*"((?:\\.|[^"\\\n])*)"\s*(?=[,)])', re.M)
LUA_SECTION = re.compile(r"^-- ([A-Z][A-Za-z &/]*?) -{3,}\s*$", re.M)


def collect_extra(catalog, origins):
    """Shell strings kept outside the shell's code: catalogue categories and
    the keybind sheet's bind descriptions and sections."""
    data = json.load(open(APP_CATALOG, encoding="utf-8")) if os.path.exists(APP_CATALOG) else {}
    for cat in data.get("categories", []):
        if isinstance(cat, dict) and isinstance(cat.get("label"), str):
            add(catalog, origins, cat["label"], cat["label"], rel(APP_CATALOG))
    for f in sorted(os.listdir(HYPR) if os.path.isdir(HYPR) else []):
        if not f.endswith(".lua"):
            continue
        path = os.path.join(HYPR, f)
        text = open(path, encoding="utf-8").read()
        code = "\n".join("" if l.lstrip().startswith("--") else l for l in text.split("\n"))
        for m in LUA_BIND.finditer(code):
            add(catalog, origins, m.group(1), m.group(1), "%s:%d" % (rel(path), text.count("\n", 0, m.start()) + 1))
        if f == "binds.lua":
            for m in LUA_SECTION.finditer(text):
                add(catalog, origins, m.group(1), m.group(1), "%s:%d" % (rel(path), text.count("\n", 0, m.start()) + 1))


def bash_files():
    roots = [os.path.join(ROOT, "bin"), os.path.join(SHARE, "lib"), os.path.join(SHARE, "omarchy"),
             os.path.join(SHARE, "layers"), os.path.join(SHELL, "plugins")]
    for top in roots:
        if not os.path.isdir(top):
            continue
        for base, dirs, files in os.walk(top):
            dirs[:] = sorted(d for d in dirs if d != "tests")
            for f in sorted(files):
                path = os.path.join(base, f)
                if f.endswith((".qml", ".js", ".json", ".md", ".py", ".lua", ".txt", ".svg", ".png", ".cjs")):
                    continue
                try:
                    head = open(path, encoding="utf-8").read(200)
                except (UnicodeDecodeError, IsADirectoryError):
                    continue
                if f.endswith(".sh") or re.match(r"#!.*\b(ba)?sh\b", head) or "shellcheck shell=" in head:
                    yield path


def collect_notify():
    catalog, origins = {}, {}
    for path in bash_files():
        if path == os.path.join(SHARE, "lib", "i18n.sh"):
            continue
        text = open(path, encoding="utf-8").read()
        where = rel(path)
        try:
            for line, (s,) in bash_calls(text, "i18n", 1):
                add(catalog, origins, s, s, "%s:%d" % (where, line))
            for line, (one, other) in bash_calls(text, "i18n_n", 2):
                add(catalog, origins, other, {"one": one, "other": other}, "%s:%d" % (where, line))
        except Failure as e:
            raise Failure("%s: %s" % (where, e))
    return catalog, origins


def strip_jsonc(text):
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == '"':
            j = i + 1
            while text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                break
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def collect_menu():
    items = json.loads(strip_jsonc(open(MENU, encoding="utf-8").read()))
    catalog = {}
    for ident, item in items.items():
        if not isinstance(item, dict) or item.get("hidden") is True:
            continue
        fields = {k: item[k] for k in ("label", "title", "description") if isinstance(item.get(k), str) and item[k].strip()}
        if fields:
            catalog[ident] = fields
    return catalog, {k: rel(MENU) for k in catalog}


COLLECTORS = {"shell": collect_shell, "menu": collect_menu, "notify": collect_notify}


# --- catalogs ---------------------------------------------------------------

def catalog_path(lang, name):
    return os.path.join(I18N, lang, name + ".json")


def dump(data):
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return None
    except ValueError as e:
        raise Failure("%s: not valid JSON: %s" % (rel(path), e))
    if not isinstance(data, dict):
        raise Failure("%s: not a JSON object" % rel(path))
    return data


def languages():
    registry = load(os.path.join(I18N, "locales.json")) or {}
    return list(registry)


def placeholders(text):
    return set(PLACEHOLDER.findall(text))


def check_value(lang, key, source, value, problems, where):
    if isinstance(source, dict):
        forms = PLURAL_FORMS.get(lang, ["other"])
        if not isinstance(value, dict):
            problems.append("%s: %r counts, so its translation is an object of %s" % (where, key, ", ".join(forms)))
            return
        allowed = placeholders(source["other"]) | placeholders(source["one"])
        for form in forms:
            text = value.get(form)
            if not isinstance(text, str) or not text.strip():
                problems.append("%s: %r lacks its %r form" % (where, key, form))
            elif not placeholders(text) <= allowed:
                problems.append("%s: %r form %r adds a placeholder" % (where, key, form))
        # The count may be written out ("one update"), but every other
        # argument must still appear in the general form.
        if isinstance(value.get("other"), str) and placeholders(value["other"]) != placeholders(source["other"]):
            problems.append("%s: %r: the 'other' form changes the placeholders" % (where, key))
        extra = set(value) - set(forms)
        if extra:
            problems.append("%s: %r has forms %s that %s never uses" % (where, key, sorted(extra), lang))
        return
    if not isinstance(value, str) or not value.strip():
        problems.append("%s: %r has no translation" % (where, key))
    elif placeholders(value) != placeholders(source):
        problems.append("%s: %r: placeholders %s, the English has %s" % (where, key, sorted(placeholders(value)), sorted(placeholders(source))))


def check_catalogs(problems):
    fresh = {}
    for name in CATALOGS:
        try:
            fresh[name], _ = COLLECTORS[name]()
        except Failure as e:
            problems.append(str(e))
            fresh[name] = None
            continue
        current = load(catalog_path("en", name))
        if current != fresh[name]:
            problems.append("%s is not what the code says: run tools/i18n.py extract" % rel(catalog_path("en", name)))
    for lang in languages():
        if lang == "en":
            continue
        for name in CATALOGS:
            source = fresh.get(name)
            if source is None:
                continue
            path = catalog_path(lang, name)
            where = rel(path)
            data = load(path)
            if data is None:
                problems.append("%s is missing" % where)
                continue
            for key in sorted(set(data) - set(source)):
                problems.append("%s: %r is not in the English catalog (stale)" % (where, key))
            for key in sorted(source):
                if key not in data:
                    problems.append("%s: %r is not translated" % (where, key))
                    continue
                if name == "menu":
                    value = data[key]
                    if not isinstance(value, dict):
                        problems.append("%s: %r is not an object" % (where, key))
                        continue
                    for field in sorted(set(value) - set(source[key])):
                        problems.append("%s: %r has a %s the menu does not" % (where, key, field))
                    for field in source[key]:
                        check_value(lang, "%s.%s" % (key, field), source[key][field], value.get(field), problems, where)
                else:
                    check_value(lang, key, source[key], data[key], problems, where)
        prov = load(os.path.join(I18N, lang, "provenance.json"))
        if prov is None:
            problems.append("%s/provenance.json is missing: say who translated %s" % (rel(os.path.join(I18N, lang)), lang))
            continue
        for field in ("translation", "translator", "date", "note"):
            if not isinstance(prov.get(field), str) or not prov[field].strip():
                problems.append("%s/provenance.json: %s is missing" % (lang, field))
        if prov.get("translation") not in ("machine", "reviewed", "partly reviewed"):
            problems.append("%s/provenance.json: translation is machine, reviewed or partly reviewed" % lang)
        reviewed = prov.get("reviewed", {})
        for name in CATALOGS:
            keys = reviewed.get(name, [])
            if not isinstance(keys, list):
                problems.append("%s/provenance.json: reviewed.%s is a list of keys" % (lang, name))
                continue
            for key in keys:
                if fresh.get(name) is not None and key not in fresh[name]:
                    problems.append("%s/provenance.json: reviewed %s key %r is not in the catalog" % (lang, name, key))


def first_argument(text, i):
    """The source text of the call argument starting at text[i], up to its
    top-level comma or closing parenthesis."""
    depth, quote, j = 0, None, i
    while j < len(text):
        c = text[j]
        if quote:
            if c == "\\":
                j += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        j += 1
    return text[i:j]


def check_hidden_literals(problems):
    """I18n.tr(cond ? "A" : "B") translates at run time, but tools/i18n.py
    collects only a literal written straight after the parenthesis, so "A"
    and "B" would never reach the catalogs: translate each branch."""
    call = re.compile(r"(?<![\w.$])I18n\.(?:tr|tn)\s*\(")
    literal = re.compile(r"([\"'])(?:\\.|(?!\1).)*[A-Za-z]{2}(?:\\.|(?!\1).)*\1")
    for path in shell_files():
        text = strip_comment_lines(open(path, encoding="utf-8").read())
        for m in call.finditer(text):
            i = skip_space(text, m.end())
            if text[i:i + 1] in "\"'":
                continue
            if literal.search(first_argument(text, i)):
                problems.append("%s:%d: a literal inside I18n.tr(…) is never collected: call I18n.tr on each literal" % (rel(path), text.count("\n", 0, m.start()) + 1))


def check_bare_text(problems):
    for path in shell_files():
        if not path.endswith(".qml"):
            continue
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if "i18n-ignore" in line:
                continue
            if line.lstrip().startswith("//"):
                continue
            for m in BARE_TEXT.finditer(line):
                value = m.group(2)
                if re.search(r"[A-Za-z]{2}", value) and re.search(r"[A-Z ]", value):
                    problems.append("%s:%d: bare English %r: wrap it in I18n.tr() (or mark the line // i18n-ignore)" % (rel(path), n, value))


# --- commands ---------------------------------------------------------------

def extract():
    for name in CATALOGS:
        catalog, _ = COLLECTORS[name]()
        path = catalog_path("en", name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(dump(catalog))
        print("%s: %d strings" % (rel(path), len(catalog)))


def check():
    problems = []
    check_catalogs(problems)
    check_bare_text(problems)
    check_hidden_literals(problems)
    for p in problems:
        print("i18n: " + p, file=sys.stderr)
    if problems:
        print("i18n: %d problems" % len(problems), file=sys.stderr)
        return 1
    print("i18n: catalogs fresh and complete for %s" % ", ".join(languages()))
    return 0


def stats():
    for lang in languages():
        prov = load(os.path.join(I18N, lang, "provenance.json")) or {}
        parts = []
        for name in CATALOGS:
            data = load(catalog_path(lang, name)) or {}
            reviewed = len(prov.get("reviewed", {}).get(name, [])) if lang != "en" else len(data)
            parts.append("%s %d (%d reviewed)" % (name, len(data), reviewed))
        print("%s: %s; %s" % (lang, prov.get("translation", "source"), ", ".join(parts)))
    return 0


def main(argv):
    if len(argv) == 4 and argv[1] == "--root":
        set_root(argv[2])
        argv = [argv[0], argv[3]]
    if len(argv) != 2 or argv[1] not in ("extract", "check", "stats"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        if argv[1] == "extract":
            extract()
            return 0
        return check() if argv[1] == "check" else stats()
    except Failure as e:
        print("i18n: " + str(e), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
