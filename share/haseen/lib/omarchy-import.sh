# shellcheck shell=bash
# omarchy-import.sh — pure translators for bin/haseen-import-omarchy. Sourced,
# never executed. Nothing here writes: every function prints its result, and
# the command decides what lands through the common.sh helpers.
#
# Reads Omarchy 4's file formats (~/.config/omarchy/shell.json, the
# hl.*/o.* Hyprland user files). No Omarchy code is copied; the helper
# semantics (o.bind runs a string as exec_cmd, { launch = X } and o.launch
# wrap X in `uwsm-app --`) follow Omarchy default/hypr/helpers.lua, whose
# haseen twin is share/haseen/default/hypr/init.lua.

[[ -n ${HASEEN_OMARCHY_IMPORT_SH:-} ]] && return 0
HASEEN_OMARCHY_IMPORT_SH=1

# A script or Lua chunk that calls an Omarchy command (omarchy-foo, or the
# `omarchy foo` router). Paths such as ~/.config/omarchy/… and identifiers such
# as omarchy_scale do not match. OMARCHY_LUA_AWK below carries the same rule.
# shellcheck disable=SC2034  # read by bin/haseen-import-omarchy
OMARCHY_CMD_ERE='(^|[^A-Za-z0-9_/.~-])omarchy(-[a-z]|[[:space:]]+[a-z])'

# Omarchy built-in bar widgets with a haseen built-in that does the same job,
# and the settings whose meaning carries over unchanged (both use Qt date
# formats for the clock). Everything else under omarchy.* that no plugin
# directory provides is dropped and reported.
# shellcheck disable=SC2016  # jq program, not shell expansions
OMARCHY_IMPORT_JQ='
def builtin_map: {
    "omarchy.workspaces": "haseen.workspaces",
    "omarchy.clock": "haseen.clock",
    "omarchy.media": "haseen.media",
    "omarchy.tray": "haseen.tray",
    "omarchy.weather": "haseen.weather",
    "omarchy.bluetooth": "haseen.bluetooth",
    "omarchy.network": "haseen.network",
    "omarchy.audio": "haseen.audio",
    "omarchy.power": "haseen.battery",
    "omarchy.indicators": "haseen.indicators"
};
# Legacy single-segment ids get the namespace haseen registers them under
# (architecture 5.4: omaconnect -> omarchy.omaconnect).
def nsid: if type == "string" and test("^[a-z0-9-]+$") then "omarchy." + . else . end;
def entry: if type == "string" then {id: .} elif type == "object" then . else {} end;
def known($id): $known | index([$id]) != null;
# Add-ons haseen has ported natively (OMARCHY_PORTED below lists the targets).
# The omagesture panel runs omagesture-apply on load, which appends a require
# block to ~/.config/hypr/hyprland.lua and binds the same touchpad gestures as
# haseen.gestures (Hyprland rejects the second binding as overshadowed), so
# the original is never listed or enabled, only replaced in place.
# OmaStats (CPU/GPU/RAM) gives way to haseen.sysusage, which reads the same
# numbers through haseen-sidecar without polling from QML (plan 032): the
# owner compared both on io and kept the haseen one (2026-10-06, plan 048).
# The OmaStats-specific settings have no meaning there and are reported.
# omapager is ported as haseen.pager (plan 025), the notification daemon
# haseen runs as a service anyway.
def superseded: {
    "io.github.heroesofcode.omagesture": "haseen.gestures",
    "crmne.omastats": "haseen.sysusage",
    "njpatel.omapager": "haseen.pager",
    "omarchy.omapager": "haseen.pager"
};
def target($oid): builtin_map[$oid] // superseded[$oid];
# "declared": every key the target manifest declares carries over under its
# own name ($declared[target] = its setting keys); the rest are reported.
def setting_map: {
    "haseen.clock": { "format": "format", "verticalFormat": "verticalFormat" },
    "haseen.indicators": { "items": "items", "indicators": "items", "alwaysShow": "alwaysShow" },
    "haseen.gestures": "declared",
    "haseen.pager": "declared"
};
def unsupported($hid; $k; $v): $hid == "haseen.gestures" and $k == "middleButton" and $v == "paste";
# An Omarchy built-in: written as omarchy.* and provided by no plugin
# directory. Judged on the id as written, since a legacy single-segment id
# (always an add-on) is only namespaced to omarchy.* by haseen.
def builtin($e): ($e.id | type) == "string" and ($e.id | startswith("omarchy.")) and (known($e.id) | not);
def note($s): .report += [$s];

def translate_settings($oid; $hid; $s):
    (setting_map[$hid] // {}) as $m
    | reduce ($s | keys_unsorted[]) as $k ({settings: {}, report: []};
        if unsupported($hid; $k; $s[$k]) then .report += ["\($oid): setting \($k) = \($s[$k] | tojson) is not supported by \($hid), dropped"]
        elif $m == "declared" then
            (if ($declared[$hid] // []) | index([$k]) then .settings[$k] = $s[$k]
             else .report += ["\($oid): setting \($k) is not a \($hid) setting, dropped"] end)
        elif $m | has($k) then .settings[$m[$k]] = $s[$k]
        else .report += ["\($oid): setting \($k) has no haseen equivalent, dropped"] end);

def place($sec; $raw):
    ($raw | entry) as $e
    | ($e.id | nsid) as $oid
    | ($e | del(.id)) as $s
    | if ($oid | type) != "string" or $oid == "" then note("bar.\($sec): an entry without an id, skipped")
      elif target($oid) != null then
        target($oid) as $hid
        | if .seen | index([$hid]) then note("\($oid): \($hid) is already in the bar, duplicate skipped")
          else translate_settings($oid; $hid; $s) as $t
            | .seen += [$hid]
            | .cfg.bar[$sec] += [$hid]
            | .report += $t.report
            | .mapped += ["\($oid) -> \($hid)"]
            | (if ($t.settings | length) > 0 then .cfg.plugins[$hid].settings = ((.cfg.plugins[$hid].settings // {}) + $t.settings) else . end)
            # haseen ships the weather widget off (it asks wttr.in); being in
            # the Omarchy bar is the opt-in, with the location Omarchy kept.
            | (if $hid == "haseen.weather" then
                 .cfg.plugins[$hid].enabled = true
                 | (if $wloc != "" then .cfg.plugins[$hid].settings.location = $wloc else . end)
               else . end)
          end
      elif builtin($e) then
        note("\($oid): Omarchy built-in with no haseen equivalent, dropped")
      elif .seen | index([$oid]) then note("\($oid): already in the bar, duplicate skipped")
      else
        .seen += [$oid]
        | .cfg.bar[$sec] += [$oid]
        | .cfg.plugins[$oid].enabled = true
        | (if ($s | length) > 0 then .cfg.plugins[$oid].settings = $s else . end)
        | .kept += [$oid]
        | (if known($oid) then . else note("\($oid): plugin not installed; haseen skips it until it is") end)
      end;

def service($raw):
    ($raw | entry) as $e
    | ($e.id | nsid) as $oid
    | ($e | del(.id)) as $s
    | if ($oid | type) != "string" or $oid == "" then note("plugins: an entry without an id, skipped")
      elif (builtin_map | has($oid)) or builtin($e) then
        note("\($oid): Omarchy built-in service with no haseen equivalent, dropped")
      elif superseded[$oid] != null then
        superseded[$oid] as $hid
        | translate_settings($oid; $hid; $s) as $t
        | .report += $t.report
        | .mapped += ["\($oid) -> \($hid)"]
        | (if ($t.settings | length) > 0 then .cfg.plugins[$hid].settings = ((.cfg.plugins[$hid].settings // {}) + $t.settings) else . end)
        | (if ($services | index([$hid])) or (.added | index([$hid])) then . else .added += [$hid] end)
      else
        .cfg.plugins[$oid].enabled = true
        | (if ($s | length) > 0 then .cfg.plugins[$oid].settings = $s else . end)
        | (if ($services | index([$oid])) or (.added | index([$oid])) then . else .added += [$oid] end)
        | (if known($oid) then . else note("\($oid): plugin not installed; haseen skips it until it is") end)
      end;

(if type == "object" then . else {} end) as $om
| ($om.bar // {} | if type == "object" then . else {} end) as $bar
| ($bar.layout // {} | if type == "object" then . else {} end) as $layout
| ($om.idle // {} | if type == "object" then . else {} end) as $idle
| {cfg: {}, seen: [], report: [], added: [], mapped: [], kept: []}
| (if $bar.position == null then .
   elif ($bar.position | IN("top", "bottom", "left", "right")) then .cfg.bar.position = $bar.position
   else note("bar.position \($bar.position | tojson) is not top, bottom, left or right, dropped") end)
| (if ($bar.transparent | type) == "boolean" then .cfg.bar.transparent = $bar.transparent
   elif $bar.transparent == null then . else note("bar.transparent is not a boolean, dropped") end)
| (if ($bar.centerAnchor // "") != "" then
     note("bar.centerAnchor (\($bar.centerAnchor)): haseen centres the centre section as a group, dropped")
   else . end)
| reduce ($bar | keys_unsorted[] | select(IN("position", "transparent", "centerAnchor", "layout") | not)) as $k (.;
    note("bar.\($k): no haseen equivalent, dropped"))
| reduce ("left", "center", "right") as $sec (.;
    if $layout | has($sec) then
      .cfg.bar[$sec] = []
      | reduce (($layout[$sec] | if type == "array" then .[] else empty end)) as $e (.; place($sec; $e))
    else . end)
# Omarchy draws notifications itself and its bar always had their state (the
# Do Not Disturb bell among the indicators). haseen keeps that in the bell of
# haseen.pager, so a right section without one gets it, right after the tray
# (the owner rule: haseen.tray leads bar.right), shown even with nothing held
# back.
| (if ($layout | has("right")) and (.seen | index(["haseen.tray"])) then
     .cfg.bar.right = (["haseen.tray"] + (.cfg.bar.right - ["haseen.tray"]))
   else . end)
| (if ($layout | has("right")) and (.seen | index(["haseen.pager"]) | not) then
     (if .cfg.bar.right[0] == "haseen.tray" then 1 else 0 end) as $at
     | .cfg.bar.right = .cfg.bar.right[0:$at] + ["haseen.pager"] + .cfg.bar.right[$at:]
     | .seen += ["haseen.pager"]
     | .mapped += ["Omarchy notifications -> haseen.pager (bell, alwaysShow)"]
     | (if (.cfg.plugins["haseen.pager"].settings // {}) | has("alwaysShow") then .
        else .cfg.plugins["haseen.pager"].settings.alwaysShow = true end)
   else . end)
| (if ($idle.screensaver | type) == "number" then .cfg.plugins["haseen.idle"].settings.screensaverAfter = ($idle.screensaver | floor) else . end)
| (if ($idle.lock | type) == "number" then .cfg.plugins["haseen.idle"].settings.lockAfter = ($idle.lock | floor) else . end)
| reduce ($idle | keys_unsorted[] | select(IN("screensaver", "lock") | not)) as $k (.;
    note("idle.\($k): no haseen equivalent, dropped"))
| reduce (($om.plugins // []) | if type == "array" then .[] else empty end) as $e (.; service($e))
| (if (.added | length) > 0 then .cfg.services = ($services + .added) else . end)
| reduce ($om | keys_unsorted[] | select(IN("version", "bar", "idle", "plugins") | not)) as $k (.;
    note("\($k): not a setting haseen imports, dropped"))
| .report |= reduce .[] as $r ([]; if index([$r]) then . else . + [$r] end)
| {config: .cfg, added, report, mapped, kept}
'

# The native ports `superseded` maps onto; the command reads their declared
# setting keys from the manifests haseen loads.
# shellcheck disable=SC2034  # read by bin/haseen-import-omarchy
OMARCHY_PORTED=(haseen.gestures haseen.pager)

# omarchy_import_shell OMARCHY_JSON KNOWN_IDS_JSON SERVICES_JSON WEATHER_LOCATION DECLARED_JSON
# — {config, added, report, mapped, kept}: config is the haseen user
# shell.json the Omarchy file amounts to; added lists the service/overlay ids
# appended to SERVICES (haseen's default services: a user array replaces the
# default one, so the whole list is written, as `haseen plugin enable` does).
# DECLARED maps each OMARCHY_PORTED id to its setting keys.
omarchy_import_shell() {
    jq --argjson known "$2" --argjson services "$3" --arg wloc "$4" --argjson declared "$5" \
        "$OMARCHY_IMPORT_JQ" <<<"$1"
}

# omarchy_import_merge USER_JSON IMPORT_JSON ADDED_JSON — the user's file with
# the import underneath: objects merge, and any key the user has set keeps
# the user's value. Two exceptions are additive, never removing an entry:
# the imported services are appended to a services list the user has set,
# and an imported bar widget that is in none of the bar's sections is put
# into the user's section next to the imported neighbour it followed (or
# preceded). A re-run therefore adds what a newer haseen maps (Omarchy's
# indicators, the pager bell) to a bar the user arranged after an earlier
# import; it also brings back an imported widget the user since removed.
omarchy_import_merge() {
    jq -n --argjson user "$1" --argjson imp "$2" --argjson added "$3" '
        def ids: if type == "array" then map(strings) else [] end;
        def insert_missing($from; $present):
            reduce range(0; $from | length) as $i (.;
                $from[$i] as $id
                | if $present | index([$id]) then .
                  else . as $cur
                    | ([$from[0:$i][] as $p | $cur | index([$p]) | values] | last) as $after
                    | ([$from[$i + 1:][] as $p | $cur | index([$p]) | values] | first) as $before
                    | if $after != null then $cur[0:$after + 1] + [$id] + $cur[$after + 1:]
                      elif $before != null then $cur[0:$before] + [$id] + $cur[$before:]
                      else $cur + [$id] end
                  end);
        ($imp * $user) as $m
        | ([$m.bar.left, $m.bar.center, $m.bar.right] | map(ids) | add) as $present
        | reduce ("left", "center", "right") as $sec ($m;
            if ($user.bar[$sec] | type) == "array" and ($imp.bar[$sec] | type) == "array"
            then .bar[$sec] |= insert_missing($imp.bar[$sec] | ids; $present) else . end)
        # haseen.tray leads bar.right; nothing is put before it.
        | if (.bar.right | type) == "array" and (.bar.right | index(["haseen.tray"]))
          then .bar.right = (["haseen.tray"] + (.bar.right - ["haseen.tray"])) else . end
        | if ($user | has("services")) and ($added | length) > 0
          then .services = ($user.services + ($added - $user.services)) else . end'
}

# Lua carry-over. The source is cut into top-level statements ("chunks"):
# bracket and block-keyword depth, ignoring strings and comments, decides
# where one ends. Each chunk is then
#   - translated: o.bind -> haseen.rebind (an Omarchy bind replaces haseen's
#     on the same key instead of both firing), o.launch / { launch = X } ->
#     haseen.launch, single-line o.launch_on_start / o.exec_on_start -> an
#     hl.on("hyprland.start") handler;
#   - skipped (and reported) when it still calls an Omarchy command or
#     helper, since those do not exist under haseen; a one-line note marks
#     the spot in the output;
#   - dropped when the destination already holds the same text outside this
#     import's block (a file carried over by hand earlier).
# Comment lines directly above a chunk (its doc) or directly below one are
# kept with it; free-standing comment blocks (Omarchy's commented-out
# examples) are not carried. Output lines: "L<TAB>text" for the block,
# "R<TAB>text" for the report.
# shellcheck disable=SC2016  # awk program, not shell expansions
OMARCHY_LUA_AWK='
function scan(line, keep_strings,    out, i, n, c, q) {
    out = ""; q = ""; n = length(line)
    for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q != "") {
            if (c == "\\") { if (keep_strings) out = out c substr(line, i + 1, 1); i++; continue }
            if (c == q) q = ""
            if (keep_strings) out = out c
            continue
        }
        if (c == "\"" || c == "\047") { q = c; if (keep_strings) out = out c; continue }
        if (c == "-" && substr(line, i + 1, 1) == "-") break
        out = out c
    }
    return out
}
function delta(line,    s, d, n, i, w, words) {
    s = scan(line, 0)
    d = gsub(/[({[]/, "&", s) - gsub(/[)}\]]/, "&", s)
    gsub(/[^A-Za-z0-9_]+/, " ", s)
    n = split(s, words, " ")
    for (i = 1; i <= n; i++) {
        w = words[i]
        if (w == "function" || w == "do" || w == "if" || w == "repeat") d++
        else if (w == "end" || w == "until") d--
    }
    return d
}
function subst_call(s, name, repl,    out, pre, rest, pos) {
    out = ""; rest = s
    while (match(rest, "(^|[^A-Za-z0-9_.])o\\." name "\\(")) {
        pos = RSTART; if (substr(rest, RSTART, 1) != "o") pos++
        out = out substr(rest, 1, pos - 1) repl "("
        rest = substr(rest, RSTART + RLENGTH)
    }
    return out rest
}
function launch_tables(s,    out, m, inner) {
    out = ""
    while (match(s, /\{[ \t]*launch[ \t]*=[ \t]*("[^"]*"|\047[^\047]*\047)[ \t]*\}/)) {
        m = substr(s, RSTART, RLENGTH)
        inner = m
        sub(/^\{[ \t]*launch[ \t]*=[ \t]*/, "", inner)
        sub(/[ \t]*\}$/, "", inner)
        out = out substr(s, 1, RSTART - 1) "haseen.launch(" inner ")"
        s = substr(s, RSTART + RLENGTH)
    }
    return out s
}
function on_start(s,    code, indent, kind, arg, open) {
    if (s ~ /\n/) return s
    code = scan(s, 1)
    sub(/[ \t]+$/, "", code)
    if (code !~ /^[ \t]*o\.(launch|exec)_on_start\(.*\)$/) return s
    indent = code; sub(/[^ \t].*$/, "", indent)
    kind = (code ~ /o\.launch_on_start/) ? "launch" : "exec"
    open = index(code, "(")
    arg = substr(code, open + 1, length(code) - open - 1)
    if (kind == "launch") arg = "haseen.launch(" arg ")"
    return indent "hl.on(\"hyprland.start\", function() hl.exec_cmd(" arg ") end)"
}
function code_of(s,    n, i, parts, out) {
    n = split(s, parts, "\n"); out = ""
    for (i = 1; i <= n; i++) out = out (i > 1 ? "\n" : "") scan(parts[i], 1)
    return out
}
function emit(text,    n, i, parts) {
    if (emitted && gap) print "L\t"
    gap = 0; emitted = 1
    n = split(text, parts, "\n")
    for (i = 1; i <= n; i++) print "L\t" parts[i]
}
function first_line(s,    t) {
    t = s; sub(/\n.*/, "", t); sub(/^[ \t]+/, "", t)
    return t
}
function finish(    t, code, why, helper) {
    t = on_start(subst_call(subst_call(launch_tables(chunk), "bind", "haseen.rebind"), "launch", "haseen.launch"))
    code = code_of(t)
    # loaders mode (an entry file such as hyprland.lua): only a block that
    # loads a generated file from the state dir comes along, so long as it
    # needs nothing of Omarchy; the bootstrap and requires around it are
    # Omarchy itself and go silently.
    if (loaders && (code !~ /(^|[^A-Za-z0-9_])(dofile|loadfile)([^A-Za-z0-9_]|$)/ ||
                    code !~ /XDG_STATE_HOME|\.local\/state/ ||
                    code ~ /(^|[^A-Za-z0-9_])require([^A-Za-z0-9_]|$)|OMARCHY_PATH/ ||
                    code ~ /(^|[^A-Za-z0-9_\/.~-])omarchy(-[a-z]|[ \t]+[a-z])/ ||
                    code ~ /(^|[^A-Za-z0-9_.])o\.[A-Za-z_]+/)) {
        comments = ""; chunk = ""; depth = 0; inchunk = 0; after = 0
        return
    }
    why = ""
    if (code ~ /(^|[^A-Za-z0-9_\/.~-])omarchy(-[a-z]|[ \t]+[a-z])/ || code ~ /\{[^}]*(omarchy|webapp|tui|focus)[ \t]*=/)
        why = "runs an Omarchy command"
    else if (match(code, /(^|[^A-Za-z0-9_.])o\.[A-Za-z_]+/)) {
        helper = substr(code, RSTART, RLENGTH); sub(/^[^o]*/, "", helper)
        why = "uses the Omarchy helper " helper
    } else if (code ~ /(^|[^A-Za-z0-9_])require[ \t]*[("]/ || code ~ /OMARCHY_PATH/)
        why = "loads Omarchy modules"
    # haseen.gestures renders its own 3-finger-up gesture unless g3Up is
    # "none"; a second hl.gesture on that axis is rejected as overshadowed.
    else if (g3up != "" && g3up != "none" && code ~ /hl\.gesture[ \t]*\(/ &&
             code ~ /fingers[ \t]*=[ \t]*3([^0-9]|$)/ && code ~ /direction[ \t]*=[ \t]*"up"/)
        why = "haseen.gestures already binds 3-finger up (g3Up = " g3up ")"
    if (why != "") {
        print "R\t" src ": " why ": " first_line(chunk)
        emit(comments "-- haseen import omarchy skipped (" why "): " first_line(chunk))
        after = 1
    } else if (index(existing, t) > 0) {
        after = 0
    } else {
        emit(comments t)
        after = 1
    }
    comments = ""; chunk = ""; depth = 0; inchunk = 0
}
function flush_comments() {
    if (comments != "" && after) emit(substr(comments, 1, length(comments) - 1))
    comments = ""; after = 0
}
FILENAME == ARGV[1] { existing = existing $0 "\n"; next }
{
    line = $0
    if (inchunk) {
        chunk = chunk "\n" line
        depth += delta(line)
        if (depth <= 0) finish()
        next
    }
    if (line ~ /^[ \t]*$/) { flush_comments(); gap = 1; next }
    if (line ~ /^[ \t]*--/) { comments = comments line "\n"; next }
    chunk = line; inchunk = 1
    depth = delta(line)
    if (depth <= 0) finish()
}
END {
    if (inchunk) finish()
    flush_comments()
}
'

# omarchy_lua_translate SRC_FILE EXISTING_TEXT_FILE LABEL [G3UP] [LOADERS] — the
# L/R stream above for SRC_FILE, checked against EXISTING_TEXT_FILE (the
# destination without this import's block). LABEL names the source in report
# lines; G3UP is the haseen.gestures g3Up setting in effect; LOADERS=1 keeps
# only the blocks that load generated state files.
omarchy_lua_translate() {
    awk -v src="$3" -v g3up="${4:-}" -v loaders="${5:-0}" "$OMARCHY_LUA_AWK" "$2" "$1"
}

# omarchy_lua_begin / omarchy_lua_end NAME — the marker lines of the block an
# import of NAME (bindings.lua, input.lua, …) owns in a destination file.
omarchy_lua_begin() { printf -- '-- >>> haseen import omarchy: %s\n' "$1"; }
omarchy_lua_end() { printf -- '-- <<< haseen import omarchy: %s\n' "$1"; }

# omarchy_lua_splice TEXT_FILE NAME BLOCK_FILE — TEXT with NAME's block
# replaced by BLOCK (removed when BLOCK is empty), or BLOCK appended after a
# blank line when TEXT has none yet. BLOCK_FILE=/dev/null gives the text
# outside the block, which is what the translator compares against.
omarchy_lua_splice() {
    awk -v begin="$(omarchy_lua_begin "$2")" -v end="$(omarchy_lua_end "$2")" '
        FILENAME == ARGV[1] { block = block $0 "\n"; next }
        $0 == begin { skipping = 1; if (!done) printf "%s", block; done = 1; next }
        skipping { if ($0 == end) skipping = 0; next }
        { print; last = $0; lines++ }
        END {
            if (!done && block != "") {
                if (lines > 0 && last != "") print ""
                printf "%s", block
            }
        }' "$3" "$1"
}
