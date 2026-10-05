# shellcheck shell=bash
# Web apps and agent crash: `haseen webapp install` writes a launcher that runs
# the default chromium-family browser in app mode with a fetched icon, refuses a
# browser without an app mode, `haseen webapp remove` deletes launcher and icon,
# and `haseen agent crash` builds its report without starting an agent.

SYSROOT="$FIXTURES/webapp"
PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

# curl that writes a real 1x1 PNG wherever -o points, so the installer's
# mime-type check passes without touching the network.
curl_stub() {
    stub curl "out=\"\"
while [ \$# -gt 0 ]; do
    case \"\$1\" in -o) out=\"\$2\"; shift ;; esac
    shift
done
[ -n \"\$out\" ] && echo '$PNG_B64' | base64 -d > \"\$out\"
exit 0"
}

desktop_of() { cat "$XDG_DATA_HOME/applications/$1.desktop"; }

# --- install -------------------------------------------------------------------
sandbox webapp-install
export HASEEN_SYSROOT="$SYSROOT"
stub xdg-settings 'echo chromium.desktop'
curl_stub

capture haseen webapp install "My App" example.com https://example.com/icon.png
assert_status "install succeeds" 0 "$STATUS"
entry="$(desktop_of "My App")"
assert_contains "Exec runs the browser in app mode" "$entry" 'Exec=/usr/bin/chromium "--app=https://example.com"'
assert_contains "Name is the app name" "$entry" 'Name=My App'
assert_contains "Icon is the safe name" "$entry" 'Icon=my-app'
assert_contains "entry is an Application" "$entry" 'Type=Application'
assert_eq "icon was stored" "yes" "$([[ -s $XDG_DATA_HOME/icons/hicolor/256x256/apps/my-app.png ]] && echo yes || echo no)"
assert_eq "icon is a PNG" "image/png" "$(file -b --mime-type "$XDG_DATA_HOME/icons/hicolor/256x256/apps/my-app.png")"

# An icon name that is already installed is used verbatim, no download.
capture haseen webapp install Theme https://theme.example applications-graphics
assert_status "icon-name install succeeds" 0 "$STATUS"
assert_contains "named icon kept" "$(desktop_of Theme)" 'Icon=applications-graphics'

# --- refusals ------------------------------------------------------------------
capture haseen webapp install "bad/name" https://example.com icon
assert_status "a '/' in the name is refused" 1 "$STATUS"
assert_contains "slash message" "$OUTPUT" "cannot contain '/'"

capture haseen webapp install Js "javascript:alert(1)" icon
assert_status "non-http URL is refused" 1 "$STATUS"
assert_contains "scheme message" "$OUTPUT" "must be http or https"

stub xdg-settings 'echo firefox.desktop'
capture haseen webapp install Fox https://example.com icon
assert_status "a browser without app mode is refused" 1 "$STATUS"
assert_contains "names the browser" "$OUTPUT" "firefox has no app mode"
assert_contains "says how to fix it" "$OUTPUT" "haseen setup default browser chromium"
assert_eq "nothing was written for it" "no" "$([[ -e $XDG_DATA_HOME/applications/Fox.desktop ]] && echo yes || echo no)"

# --- dry run -------------------------------------------------------------------
sandbox webapp-dry
export HASEEN_SYSROOT="$SYSROOT"
stub xdg-settings 'echo chromium.desktop'
capture haseen webapp install Dry https://dry.example --dry-run
assert_status "dry-run install succeeds" 0 "$STATUS"
assert_dry_pure "install" "$OUTPUT"
assert_contains "dry-run plans the launcher" "$OUTPUT" "DRYRUN: write $XDG_DATA_HOME/applications/Dry.desktop"
assert_contains "dry-run shows the Exec" "$OUTPUT" '--app=https://dry.example'
assert_contains "dry-run plans the icon" "$OUTPUT" "DRYRUN: download icon"
assert_eq "dry-run wrote nothing" "no" "$([[ -e $XDG_DATA_HOME/applications/Dry.desktop ]] && echo yes || echo no)"

# --- remove --------------------------------------------------------------------
sandbox webapp-remove
export HASEEN_SYSROOT="$SYSROOT"
stub xdg-settings 'echo chromium.desktop'
curl_stub
capture haseen webapp install "My App" https://example.com https://example.com/icon.png
assert_status "install for removal" 0 "$STATUS"

capture haseen webapp remove
assert_status "no name lists the web apps" 2 "$STATUS"
assert_contains "listing names the app" "$OUTPUT" "My App"

capture haseen webapp remove "My App" --dry-run
assert_status "dry-run remove succeeds" 0 "$STATUS"
assert_dry_pure "remove" "$OUTPUT"
assert_contains "dry-run plans the delete" "$OUTPUT" "DRYRUN: rm -f $XDG_DATA_HOME/applications/My App.desktop"
assert_eq "dry-run kept the launcher" "yes" "$([[ -e "$XDG_DATA_HOME/applications/My App.desktop" ]] && echo yes || echo no)"

capture haseen webapp remove "My App"
assert_status "remove succeeds" 0 "$STATUS"
assert_eq "launcher deleted" "no" "$([[ -e "$XDG_DATA_HOME/applications/My App.desktop" ]] && echo yes || echo no)"
assert_eq "icon deleted" "no" "$([[ -e "$XDG_DATA_HOME/icons/hicolor/256x256/apps/my-app.png" ]] && echo yes || echo no)"

capture haseen webapp remove "My App"
assert_status "removing an unknown app fails" 1 "$STATUS"
assert_contains "unknown app message" "$OUTPUT" "no web app named"

# --- agent crash ---------------------------------------------------------------
sandbox agent-crash
export HASEEN_SYSROOT="$SYSROOT"
stub coredumpctl 'echo "Mon 2026-10-05 11:22:33 CEST 1516893 1000 1000 SIGSEGV present /usr/bin/nautilus"'
stub claude 'echo "AGENT-RAN: $*"'

capture env HASEEN_AGENT=claude haseen agent crash 1516893 nautilus /usr/bin/nautilus SIGSEGV --dry-run
assert_status "agent crash dry-run succeeds" 0 "$STATUS"
assert_dry_pure "agent crash" "$OUTPUT"
assert_not_contains "no agent was started" "$OUTPUT" "AGENT-RAN"
assert_contains "report names the process" "$OUTPUT" "process:  nautilus"
assert_contains "report has the PID" "$OUTPUT" "PID:      1516893"
assert_contains "report has the binary" "$OUTPUT" "binary:   /usr/bin/nautilus"
assert_contains "report has the signal" "$OUTPUT" "signal:   SIGSEGV"
assert_contains "report has the crash time from coredumpctl" "$OUTPUT" "time:     Mon 2026-10-05 11:22:33 CEST"
assert_contains "report points at the skill" "$OUTPUT" "diagnose-crash"
assert_contains "dry-run plans the agent" "$OUTPUT" "DRYRUN: claude --prompt"

capture env HASEEN_AGENT=claude haseen agent crash not-a-pid --dry-run
assert_status "a non-PID is refused" 1 "$STATUS"
assert_contains "non-PID message" "$OUTPUT" "Not a PID"

capture env HASEEN_AGENT= haseen agent crash 1516893 --dry-run
assert_status "no configured agent fails" 1 "$STATUS"
assert_contains "names the setup command" "$OUTPUT" "haseen setup default agent"

unset HASEEN_SYSROOT
