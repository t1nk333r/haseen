# shellcheck shell=bash
source "$FIXTURES/vapt-lib.sh"
# jq is also an inventory tool and therefore stubbed; assertions use the host
# JSON reader explicitly, while discovered fixture executables remain inert.
jq() { /usr/bin/jq "$@"; }
workflow_fixture() {
    vapt_sandbox "$1"
    vapt_root
    vapt_home_in_root
    vapt_repos 'extra|nmap|1-1|https://nmap.org' 'extra|wordlists|1-1|https://example.org/wordlists' \
        'extra|openssh|1-1|https://www.openssh.com/'
    vapt_installed 'nmap|1-1|https://nmap.org||||usr/bin/scan-one,usr/bin/scan-two,usr/share/man/man1/scan-one.1,usr/share/doc/nmap/scan-two.txt,usr/share/applications/nmap.desktop' \
        'wordlists|1-1|https://example.org/wordlists||||usr/share/wordlists/sample.txt' \
        'openssh|1-1|https://www.openssh.com/||||usr/bin/ssh-client'
    mkdir -p "$ROOT/usr/bin" "$ROOT/usr/share/man/man1" "$ROOT/usr/share/doc/nmap" \
        "$ROOT/usr/share/wordlists" "$ROOT/usr/share/applications"
    _vapt_stub_log "$ROOT/usr/bin/scan-one" scan-one
    _vapt_stub_log "$ROOT/usr/bin/scan-two" scan-two
    _vapt_stub_log "$ROOT/usr/bin/ssh-client" ssh-client
    printf '.TH SCAN-ONE 1\nOwned usage, not a command.\n' >"$ROOT/usr/share/man/man1/scan-one.1"
    printf 'Second owned usage.\n' >"$ROOT/usr/share/doc/nmap/scan-two.txt"
    printf 'data\n' >"$ROOT/usr/share/wordlists/sample.txt"
    printf '[Desktop Entry]\nType=Application\nName=Inventory fixture\nExec=do-not-execute\n' >"$ROOT/usr/share/applications/nmap.desktop"
    mkdir -p "$ROOT$XDG_CONFIG_HOME/haseen" "$ROOT$XDG_STATE_HOME/haseen/vapt"
}
workflow_no_calls() {
    assert_eq "$1: no owned entry ran" '' "$(vapt_calls scan-one)$(vapt_calls scan-two)$(vapt_calls ssh-client)"
    vapt_tools_untouched "$1"
}
