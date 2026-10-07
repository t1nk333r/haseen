# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen setup dotfiles (plan 055): a yadm repo cloned into a home that already
# has files. Conflicts are backed up before the repo wins, an Omarchy
# hyprland.lua never replaces haseen's seed, plugin sources are never
# rewritten, an Omarchy config triggers the import, and a yadm repo with
# another remote is refused. yadm and pacman are stubs; the repo is a local
# bare git repository built here.
IMPORT_FIXTURE="$FIXTURES/omarchy-import"
SEED="$HASEEN_PATH/default/hypr/user/hyprland.lua"
REAL_GIT="$(PATH=/usr/local/bin:/usr/bin:/bin type -P git)"
export HASEEN_INLINE=1
export OMARCHY_PATH="$IMPORT_FIXTURE/sysroot/usr/share/omarchy"

# --- fixture: a bare repo with an Omarchy-era `main` and a haseen `haseen` ---
FIX="$OUT/dotfiles-fixture"
rm -rf "$FIX"
mkdir -p "$FIX/src"
fgit() { "$REAL_GIT" -C "$FIX/src" -c user.name=fixture -c user.email=fixture@example.invalid "$@"; }
fput() { # PATH CONTENT
    mkdir -p "$(dirname "$FIX/src/$1")"
    printf '%s\n' "$2" >"$FIX/src/$1"
}
fgit init -q -b main
fput .bashrc 'export EDITOR=nvim # from the dotfiles'
fput .gitconfig $'[user]\n\tname = Fixture'
fput .config/kitty/kitty.conf 'font_size 11'
fput .config/mpv/mpv.conf 'hwdec=auto'
mkdir -p "$FIX/src/.config/hypr" "$FIX/src/.config/omarchy/plugins/me.keep" "$FIX/src/.config/omarchy/plugins/me.new"
cp "$IMPORT_FIXTURE/hypr.omarchy-20261006"/{hyprland,bindings,monitors}.lua "$FIX/src/.config/hypr/"
cp "$IMPORT_FIXTURE/omarchy/shell.json" "$FIX/src/.config/omarchy/shell.json"
fput .config/omarchy/plugins/me.keep/manifest.json '{"id":"me.keep","version":"2"}'
fput .config/omarchy/plugins/me.new/manifest.json '{"id":"me.new","version":"1"}'
fgit add -A
fgit commit -q -m main
fgit switch -q -c haseen
{
    cat "$SEED"
    echo "-- from the dotfiles"
} >"$FIX/src/.config/hypr/hyprland.lua"
printf '%s\n' 'haseen.bind("SUPER + RETURN", "Terminal", "uwsm-app -- kitty")' >"$FIX/src/.config/hypr/bindings.lua"
fput .config/haseen/shell.json '{"bar":{"position":"top"}}'
fgit add -A
fgit commit -q -m haseen
fgit switch -q main
"$REAL_GIT" clone -q --bare "$FIX/src" "$FIX/dotfiles.git"
URL="$FIX/dotfiles.git"

# dot_sandbox NAME — a haseen home (seeded hyprland.lua, own monitors.lua, an
# Omarchy plugin) with stubs: git is real, pacman installs yadm by marker,
# yadm does what `yadm clone` does with git underneath.
dot_sandbox() {
    sandbox "$1"
    export DOT_LOG="$SANDBOX"
    stub git "exec '$REAL_GIT' \"\$@\""
    cat >"$SANDBOX/stubs/pacman" <<'EOF'
#!/bin/sh
case "$1" in
-Qq) [ -e "$DOT_LOG/yadm-installed" ] ;;
-S) echo "pacman $*" >>"$DOT_LOG/pacman.log" && touch "$DOT_LOG/yadm-installed" ;;
*) echo "STUB-CALLED: pacman $*" >&2; exit 97 ;;
esac
EOF
    cat >"$SANDBOX/stubs/yadm" <<'EOF'
#!/bin/sh
repo="${XDG_DATA_HOME:-$HOME/.local/share}/yadm/repo.git"
echo "yadm $*" >>"$DOT_LOG/yadm.log"
g() { git --git-dir="$repo" --work-tree="$HOME" "$@"; }
case "$1" in
introspect) echo "$repo" ;;
clone)
    shift
    b=""
    while [ $# -gt 1 ]; do
        case "$1" in -b) b="$2" && shift ;; esac
        shift
    done
    [ -e "$repo" ] && { echo "ERROR: Git repo already exists. [$repo]" >&2; exit 1; }
    if [ -n "$b" ]; then git clone -q --bare -b "$b" "$1" "$repo"; else git clone -q --bare "$1" "$repo"; fi || exit 1
    g config core.bare false && g config core.worktree "$HOME" && g config status.showUntrackedFiles no
    g reset -q
    # Like yadm: check out only what is missing; differing files stay.
    g ls-files --deleted | while IFS= read -r f; do g checkout -- ":/$f"; done
    ;;
bootstrap) touch "$DOT_LOG/bootstrap-ran" ;;
*) exec git --git-dir="$repo" --work-tree="$HOME" "$@" ;;
esac
EOF
    chmod +x "$SANDBOX/stubs/pacman" "$SANDBOX/stubs/yadm"
    mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy/plugins/me.keep" "$HOME/.config/mpv/mpv.conf"
    cp "$SEED" "$HOME/.config/hypr/hyprland.lua"
    printf '%s\n' '-- haseen monitors' >"$HOME/.config/hypr/monitors.lua"
    printf '%s\n' 'old local bashrc' >"$HOME/.bashrc"
    printf '[user]\n\tname = Fixture\n' >"$HOME/.gitconfig"
    printf '%s\n' '{"id":"me.keep","version":"1"}' >"$HOME/.config/omarchy/plugins/me.keep/manifest.json"
}
home_sum() { (cd "$HOME" && find . -printf '%p %m\n' -type f -exec sha256sum {} \; | LC_ALL=C sort | sha256sum); }
backup_of() { compgen -G "$XDG_STATE_HOME/haseen/dotfiles-backup/*/$1" | head -n1; }

# --- usage -------------------------------------------------------------------
dot_sandbox dotfiles-usage
capture haseen-setup-dotfiles --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help names the backup dir" "$OUTPUT" "dotfiles-backup/<timestamp>/"
capture haseen-setup-dotfiles
assert_status "no URL is a usage error" 2 "$STATUS"
capture haseen-setup-dotfiles status
assert_status "status without a repo" 0 "$STATUS"
assert_contains "status without a repo says so" "$OUTPUT" "dotfiles: not set up"

# --- dry run: the plan, nothing changed ----------------------------------------
dot_sandbox dotfiles-dry
before="$(home_sum)"
capture haseen-setup-dotfiles "$URL" --dry-run
assert_status "dry run" 0 "$STATUS"
assert_dry_pure "dry run" "$OUTPUT"
assert_eq "dry run: home unchanged" "$before" "$(home_sum)"
assert_eq "dry run: no yadm repo" "" "$(compgen -G "$XDG_DATA_HOME/yadm/*" || true)"
assert_not_contains "dry run: yadm never clones" "$(cat "$DOT_LOG/yadm.log" 2>/dev/null)" "clone"
assert_contains "plan: counts" "$OUTPUT" "10 files: 3 new, 1 already identical, 1 replaced"
assert_contains "plan: new files by directory" "$OUTPUT" "  ~/.config/omarchy"
assert_contains "plan: the conflict is listed for backup" "$OUTPUT" $'after a backup to '"$XDG_STATE_HOME/haseen/dotfiles-backup/"
assert_contains "plan: .bashrc is replaced" "$OUTPUT" $'\n    ~/.bashrc\n'
assert_contains "plan: Omarchy hyprland.lua keeps haseen's" "$OUTPUT" "repo's hyprland.lua does not load haseen"
assert_contains "plan: haseen's monitors.lua is kept" "$OUTPUT" $'Kept (haseen\'s, differ from the repo):\n    ~/.config/hypr/hyprland.lua\n    ~/.config/hypr/monitors.lua'
assert_contains "plan: Omarchy bindings.lua is not placed" "$OUTPUT" $'Not placed (the repo\'s, Omarchy format):\n    ~/.config/hypr/bindings.lua'
assert_contains "plan: a plugin source is never replaced" "$OUTPUT" $'never rewritten):\n    ~/.config/omarchy/plugins/me.keep/manifest.json'
assert_contains "plan: a directory in the way is skipped" "$OUTPUT" $'in the way):\n    ~/.config/mpv/mpv.conf'
assert_contains "plan: yadm is installed from the repos" "$OUTPUT" "DRYRUN: sudo pacman -S --needed yadm"
assert_contains "plan: the backup copy" "$OUTPUT" "DRYRUN: cp -a --parents -- .bashrc $XDG_STATE_HOME/haseen/dotfiles-backup/"
assert_contains "plan: yadm clone without bootstrap" "$OUTPUT" "DRYRUN: yadm clone --no-bootstrap $URL"
assert_contains "plan: the repo wins after the backup" "$OUTPUT" "DRYRUN: yadm checkout -- .bashrc"
assert_contains "plan: Omarchy hypr files go back out" "$OUTPUT" "DRYRUN: rm -f -- .config/hypr/bindings.lua"
assert_contains "plan: the import runs with the repo's hypr" "$OUTPUT" "haseen-import-omarchy --merge --hypr $XDG_STATE_HOME/haseen/dotfiles-omarchy/"
assert_contains "plan: bootstrap only on request" "$OUTPUT" "yadm bootstrap: not run (pass --bootstrap to run it)"
assert_not_contains "plan: no bootstrap call" "$OUTPUT" "DRYRUN: yadm bootstrap"
# yadm runs from $HOME, so a relative local path is made absolute first.
capture bash -c 'cd "$1" && haseen-setup-dotfiles dotfiles.git --dry-run' _ "$FIX"
assert_contains "a relative repo path is cloned by its absolute path" "$OUTPUT" "DRYRUN: yadm clone --no-bootstrap $URL"

# --- clone: backup, the repo wins, haseen's seed stays, import runs --------------
dot_sandbox dotfiles-clone
stub sudo 'exec "$@"'
capture haseen-setup-dotfiles "$URL" --yes
assert_status "clone" 0 "$STATUS"
assert_contains "yadm installed through pkg_install" "$(cat "$DOT_LOG/pacman.log" 2>/dev/null)" "pacman -S --needed --noconfirm yadm"
assert_contains "yadm clone --no-bootstrap" "$(cat "$DOT_LOG/yadm.log")" "yadm clone --no-bootstrap $URL"
assert_eq "the repo's .bashrc wins" "export EDITOR=nvim # from the dotfiles" "$(<"$HOME/.bashrc")"
bak="$(backup_of .bashrc)"
assert_eq "the old .bashrc is backed up first" "old local bashrc" "$(cat "$bak" 2>/dev/null)"
assert_eq "only conflicts are backed up" "" "$(compgen -G "$XDG_STATE_HOME/haseen/dotfiles-backup/*/.gitconfig" || true)"
assert_eq "haseen's hyprland.lua is kept" "$(<"$SEED")" "$(<"$HOME/.config/hypr/hyprland.lua")"
assert_contains "haseen's monitors.lua is kept" "$(<"$HOME/.config/hypr/monitors.lua")" "-- haseen monitors"
assert_not_contains "Omarchy's bindings.lua is not loaded by haseen" "$(cat "$HOME/.config/hypr/bindings.lua" 2>/dev/null)" "Keep only your personal keybinding overrides"
assert_eq "the plugin source is not rewritten" '{"id":"me.keep","version":"1"}' "$(<"$HOME/.config/omarchy/plugins/me.keep/manifest.json")"
assert_eq "a new plugin file is added" '{"id":"me.new","version":"1"}' "$(cat "$HOME/.config/omarchy/plugins/me.new/manifest.json" 2>/dev/null)"
assert_eq "a new file lands" "font_size 11" "$(cat "$HOME/.config/kitty/kitty.conf" 2>/dev/null)"
assert_eq "the directory in the way stays" "dir" "$([[ -d $HOME/.config/mpv/mpv.conf ]] && echo dir)"
ohypr="$(compgen -G "$XDG_STATE_HOME/haseen/dotfiles-omarchy/*/.config/hypr" | head -n1)"
assert_eq "the repo's Omarchy hypr is copied for the import" "$(<"$IMPORT_FIXTURE/hypr.omarchy-20261006/bindings.lua")" "$(cat "$ohypr/bindings.lua" 2>/dev/null)"
assert_contains "the Omarchy import ran" "$OUTPUT" "Imported:"
assert_contains "the import carried the repo's bindings" "$OUTPUT" "hypr/bindings.lua -> bindings.lua"
assert_contains "the import wrote haseen's shell.json" "$(cat "$XDG_CONFIG_HOME/haseen/shell.json" 2>/dev/null)" "t1nk33r.active-window"
assert_eq "no bootstrap without --bootstrap" "" "$(compgen -G "$DOT_LOG/bootstrap-ran" || true)"
assert_contains "the kept hypr dir is explained" "$OUTPUT" "/.config/hypr stays: \`yadm status\` lists it as changed"

# --- status ---------------------------------------------------------------------
capture haseen-setup-dotfiles status
assert_status "status" 0 "$STATUS"
assert_contains "status: remote" "$OUTPUT" "remote:   $URL"
assert_contains "status: branch" "$OUTPUT" "branch:   main"
# hyprland.lua and monitors.lua (haseen's), bindings.lua (the import's),
# me.keep (the plugin source) and mpv.conf (a directory) differ from the repo.
assert_contains "status: changed files" "$OUTPUT" "changed:  5"

# --- an existing yadm repo -----------------------------------------------------------
capture haseen-setup-dotfiles "$URL/" --yes
assert_status "same remote: nothing to do" 0 "$STATUS"
assert_contains "same remote: says so" "$OUTPUT" "yadm already manages"
assert_eq "same remote: yadm clones once" "1" "$(grep -c 'yadm clone' "$DOT_LOG/yadm.log")"
capture haseen-setup-dotfiles "$FIX/other.git" --yes
assert_status "different remote: refused" 1 "$STATUS"
assert_contains "different remote: names both" "$OUTPUT" "with remote '$URL', not $FIX/other.git; refusing"
capture haseen-setup-dotfiles "$FIX/other.git" --dry-run
assert_status "different remote: refused under --dry-run too" 1 "$STATUS"

# --- a haseen branch: its hyprland.lua wins, no import, bootstrap on request ---------
dot_sandbox dotfiles-branch
stub sudo 'exec "$@"'
capture haseen-setup-dotfiles "$URL" --branch haseen --bootstrap --yes
assert_status "branch clone" 0 "$STATUS"
assert_contains "branch: clone -b" "$(cat "$DOT_LOG/yadm.log")" "yadm clone --no-bootstrap -b haseen $URL"
assert_contains "branch: a hyprland.lua that loads haseen wins" "$(<"$HOME/.config/hypr/hyprland.lua")" "-- from the dotfiles"
assert_eq "branch: haseen's seed is backed up" "$(<"$SEED")" "$(cat "$(backup_of .config/hypr/hyprland.lua)" 2>/dev/null)"
assert_contains "branch: the repo's bindings.lua lands" "$(cat "$HOME/.config/hypr/bindings.lua" 2>/dev/null)" "haseen.bind"
assert_contains "branch: import skipped for a haseen repo" "$OUTPUT" "Omarchy import: skipped"
assert_not_contains "branch: the import did not run" "$OUTPUT" "Imported:"
assert_eq "branch: --bootstrap runs yadm bootstrap" "yes" "$([[ -e $DOT_LOG/bootstrap-ran ]] && echo yes)"
capture haseen-setup-dotfiles status
assert_contains "branch: status shows the branch" "$OUTPUT" "branch:   haseen"
