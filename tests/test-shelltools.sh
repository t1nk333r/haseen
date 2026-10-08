# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Shell tools: the packages, the rc fragment (default/shell/*.sh), the one-line
# include seed (seeds/60-shell.sh) and the multiplexer resolver.
sandbox shelltools

SHELLDIR="$HASEEN_PATH/default/shell"
PKGS="$HASEEN_PATH/layers/base/packages.txt"
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"

# --- packages ----------------------------------------------------------------
for p in zoxide eza bat; do
    assert_eq "base installs $p" "1" "$(grep -c "^$p " "$PKGS")"
    assert_eq "$p says why it is there" "yes" \
        "$(grep "^$p " "$PKGS" | grep -q '#.\{20,\}' && echo yes)"
done
# The developer CLIs are offered, not installed by default (owner, 2026-10-08).
for p in tealdeer yt-dlp lazygit dua-cli github-cli mise; do
    assert_eq "base does not install $p" "0" "$(grep -c "^$p " "$PKGS")"
    assert_eq "the catalogue offers $p" "1" \
        "$(jq --arg p "$p" '[.entries[] | select(.source == "pacman" and .ref == $p)] | length' "$HASEEN_PATH/default/catalog.json")"
done
assert_eq "fastfetch is not shipped (haseen about covers it)" "0" "$(grep -c '^fastfetch' "$PKGS")"
assert_eq "no launcher duplicate is shipped" "0" "$(grep -cE '^(walker|elephant)' "$PKGS")"

# --- the fragment parses in both shells ---------------------------------------
for f in "$SHELLDIR"/*.sh; do
    capture bash -n "$f"
    assert_status "bash -n ${f##*/}" 0 "$STATUS"
    if command -v zsh >/dev/null 2>&1; then
        capture zsh -n "$f"
        assert_status "zsh -n ${f##*/}" 0 "$STATUS"
    fi
done
command -v zsh >/dev/null 2>&1 || echo "  (note: zsh is not installed; zsh -n was skipped)"

# --- every function is defined ------------------------------------------------
# A bare PATH: none of the optional tools exist, which is also the "missing
# tool" case below.
BARE="$SANDBOX/bare"
mkdir -p "$BARE"
# git is deliberately absent here: the sandbox's git is a stub, and the
# worktree test below names the real binary itself.
for c in bash sh env dirname pwd basename grep sed awk sort tr tar gzip rm cat ls; do
    [[ -e $BARE/$c ]] || ln -s "$(PATH=/usr/bin:/bin command -v "$c")" "$BARE/$c" 2>/dev/null || true
done

# source_fragment PATHVALUE COMMAND... — source init.sh with that PATH, then run.
source_fragment() {
    local path="$1"
    shift
    capture env -i HOME="$HOME" PATH="$path" bash --noprofile --norc -c \
        ". '$SHELLDIR/init.sh'; $*"
}

source_fragment "$BARE" 'declare -F | sed "s/^declare -f //" | sort | tr "\n" " "'
assert_status "the fragment sources cleanly with no tools installed" 0 "$STATUS"
for fn in compress decompress ga gd fip dip lip rsw lsw dsw \
    tdl tds tdlm tsl hdl hds hdlm hsl ff _haseen_mux; do
    assert_contains "$fn is defined" "$OUTPUT" "$fn"
done

# --- command -v guards: a missing tool is a no-op -----------------------------
source_fragment "$BARE" 'alias; echo "MANPAGER=${MANPAGER:-}"'
assert_status "no tool, no error" 0 "$STATUS"
assert_not_contains "no ls alias without eza" "$OUTPUT" "alias ls="
assert_not_contains "no man pager without bat" "$OUTPUT" "MANPAGER=sh"
assert_eq "and nothing is printed at all" "MANPAGER=" "$OUTPUT"

# With the tools present the wiring appears.
TOOLED="$SANDBOX/tooled"
mkdir -p "$TOOLED"
cp -a "$BARE"/. "$TOOLED/"
printf '#!/bin/sh\necho "eza $*"\n' >"$TOOLED/eza"
printf '#!/bin/sh\necho "bat $*"\n' >"$TOOLED/bat"
# init.sh evals what these print, so they report themselves as a variable.
printf '#!/bin/sh\necho "ZOXIDE_INIT_FOR=$2"\n' >"$TOOLED/zoxide"
printf '#!/bin/sh\necho "MISE_ACTIVATE_FOR=$2"\n' >"$TOOLED/mise"
chmod +x "$TOOLED/eza" "$TOOLED/bat" "$TOOLED/zoxide" "$TOOLED/mise"
source_fragment "$TOOLED" 'alias; echo "MANPAGER=$MANPAGER"; echo "zoxide=$ZOXIDE_INIT_FOR mise=$MISE_ACTIVATE_FOR"'
assert_contains "eza backs ls" "$OUTPUT" "eza -lh --group-directories-first"
assert_contains "eza backs lsa" "$OUTPUT" "alias lsa="
assert_contains "eza backs lt" "$OUTPUT" "eza --tree"
assert_contains "eza backs lta" "$OUTPUT" "alias lta="
assert_contains "bat is the man pager" "$OUTPUT" "MANPAGER=sh -c 'col -bx | bat -l man -p'"
assert_contains "zoxide is initialised for this shell" "$OUTPUT" "zoxide=bash"
assert_contains "mise is activated, not advised" "$OUTPUT" "mise=bash"

# ff needs fzf and says so rather than failing obscurely.
source_fragment "$BARE" 'ff; echo "rc=$?"'
assert_contains "ff without fzf explains itself" "$OUTPUT" "ff: needs fzf"
assert_contains "ff without fzf fails" "$OUTPUT" "rc=1"

# --- the multiplexer resolver -------------------------------------------------
MUX="$SANDBOX/mux"
mkdir -p "$MUX"
cp -a "$BARE"/. "$MUX/"
printf '#!/bin/sh\necho "herdr $*"\n' >"$MUX/herdr"
printf '#!/bin/sh\necho "tmux $*"\n' >"$MUX/tmux"
chmod +x "$MUX/herdr" "$MUX/tmux"

mux_says() { # PATH ENV... -- COMMAND
    local path="$1"
    shift
    capture env -i HOME="$HOME" PATH="$path" "$@" bash --noprofile --norc -c \
        ". '$SHELLDIR/init.sh'; _haseen_mux"
}

mux_says "$MUX"
assert_eq "both installed: herdr wins" "herdr" "$OUTPUT"
mux_says "$MUX" TMUX=/tmp/tmux-1000/default,1,0
assert_eq "inside tmux: the session you are in wins" "tmux" "$OUTPUT"
mux_says "$MUX" HERDR_PANE_ID=p1 TMUX=/tmp/tmux-1000/default,1,0
assert_eq "inside herdr: herdr wins" "herdr" "$OUTPUT"

TMUX_ONLY="$SANDBOX/tmuxonly"
mkdir -p "$TMUX_ONLY"
cp -a "$BARE"/. "$TMUX_ONLY/"
cp "$MUX/tmux" "$TMUX_ONLY/tmux"
mux_says "$TMUX_ONLY"
assert_eq "only tmux installed: tmux" "tmux" "$OUTPUT"
mux_says "$BARE"
assert_eq "neither installed: no answer" "" "$OUTPUT"
assert_status "and the resolver fails" 1 "$STATUS"

# The seeded preference file beats the installed-binary probe.
mkdir -p "$HOME/.config/haseen"
echo tmux >"$HOME/.config/haseen/mux"
mux_says "$MUX"
assert_eq "the user's ~/.config/haseen/mux wins over the probe" "tmux" "$OUTPUT"
mux_says "$MUX" HERDR_PANE_ID=p1
assert_eq "but not over the session you are in" "herdr" "$OUTPUT"
echo "nonsense" >"$HOME/.config/haseen/mux"
mux_says "$MUX"
assert_eq "an unknown preference is ignored, not fatal" "herdr" "$OUTPUT"
rm -f "$HOME/.config/haseen/mux"

# Both name sets reach the same resolver, so tdl outside a session complains
# about herdr when herdr is the one haseen picked.
capture env -i HOME="$HOME" PATH="$MUX" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; tdl claude"
assert_contains "tdl routes to herdr when both are installed" "$OUTPUT" "start herdr first"
capture env -i HOME="$HOME" PATH="$TMUX_ONLY" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; hdl claude"
assert_contains "hdl falls back to tmux where that is all there is" "$OUTPUT" "start tmux first"
capture env -i HOME="$HOME" PATH="$BARE" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; tdl claude"
assert_contains "with neither, the layouts say so" "$OUTPUT" "neither herdr nor tmux is installed"

# --- the seed: one line, idempotent, never rewrites ---------------------------
INCLUDE="$HASEEN_PATH/default/shell/init.sh"
capture haseen seed user --dry-run
assert_status "a dry run succeeds" 0 "$STATUS"
assert_dry_pure "seed dry run" "$OUTPUT"
assert_contains "the rc append is planned" "$OUTPUT" "DRYRUN: append to $HOME/.bashrc:"
assert_contains "the plan shows the include line" "$OUTPUT" "| [ -r \"$INCLUDE\" ] && . \"$INCLUDE\""
assert_eq "the dry run wrote no rc" "" "$([[ -e $HOME/.bashrc ]] && echo yes)"
assert_not_contains "no zshrc is planned for a user without one" "$OUTPUT" ".zshrc"

printf '# my own rc\nexport MINE=1\n' >"$HOME/.bashrc"
capture haseen seed user
assert_status "seeding succeeds" 0 "$STATUS"
assert_eq "the include landed exactly once" "1" "$(grep -cF "$INCLUDE" "$HOME/.bashrc")"
assert_contains "the user's own rc is untouched" "$(cat "$HOME/.bashrc")" $'# my own rc\nexport MINE=1'
assert_eq "the include is the last line" "[ -r \"$INCLUDE\" ] && . \"$INCLUDE\"" "$(tail -n1 "$HOME/.bashrc")"

capture haseen seed user
assert_status "a second run succeeds" 0 "$STATUS"
assert_eq "and appends nothing" "1" "$(grep -cF "$INCLUDE" "$HOME/.bashrc")"
capture haseen seed user --dry-run
assert_not_contains "a re-run plans no rc append" "$OUTPUT" "append to $HOME/.bashrc"

# A zshrc is only written when the user already has one.
printf '# zsh of mine\n' >"$HOME/.zshrc"
capture haseen seed user
assert_eq "an existing zshrc gets the same one line" "1" "$(grep -cF "$INCLUDE" "$HOME/.zshrc")"
assert_contains "and keeps its content" "$(cat "$HOME/.zshrc")" "# zsh of mine"
capture haseen seed user
assert_eq "the zshrc append is idempotent too" "1" "$(grep -cF "$INCLUDE" "$HOME/.zshrc")"

capture haseen seed user --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help names the rc" "$OUTPUT" "$HOME/.bashrc"

# A rc that sources haseen is a rc that activates mise: no advice is printed.
stub mise 'echo "STUB-CALLED: mise $*" >&2; exit 97'
capture env HASEEN_INLINE=1 haseen install dev python --dry-run
assert_status "a mise toolchain dry run succeeds" 0 "$STATUS"
assert_contains "the toolchain is planned" "$OUTPUT" "DRYRUN: mise use --global python@latest"
assert_not_contains "an rc that includes haseen gets no mise advice" "$OUTPUT" "mise tools reach PATH"
mv "$HOME/.bashrc" "$HOME/.bashrc.mine"
mv "$HOME/.zshrc" "$HOME/.zshrc.mine"
capture env HASEEN_INLINE=1 haseen install dev python --dry-run
assert_contains "without the include, the advice is to seed, not to hand-edit" "$OUTPUT" \
    "mise tools reach PATH through haseen's shell fragment: run 'haseen seed user'"
assert_not_contains "no hand-edited rc line is suggested" "$OUTPUT" "add to ~/.bashrc"
mv "$HOME/.bashrc.mine" "$HOME/.bashrc"
mv "$HOME/.zshrc.mine" "$HOME/.zshrc"

# --- the fragment really works ------------------------------------------------
WORK="$SANDBOX/work"
mkdir -p "$WORK"
echo "round trip" >"$WORK/payload.txt"
capture env -i HOME="$HOME" PATH="$BARE" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; cd '$WORK' && compress payload.txt && rm payload.txt && decompress payload.txt.tar.gz && cat payload.txt"
assert_status "compress/decompress round-trips" 0 "$STATUS"
assert_contains "the file comes back" "$OUTPUT" "round trip"
assert_eq "the archive is beside the file" "yes" "$([[ -f $WORK/payload.txt.tar.gz ]] && echo yes)"
capture env -i HOME="$HOME" PATH="$BARE" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; compress"
assert_contains "compress without an argument explains itself" "$OUTPUT" "Usage: compress"
assert_status "and fails" 1 "$STATUS"

# ga/gd against a throwaway repository. git is stubbed in the sandbox PATH, so
# the real binary is named explicitly for the fixture repo.
GIT="$(PATH=/usr/bin:/bin command -v git)"
REPOD="$SANDBOX/wt/project"
mkdir -p "$REPOD"
(
    cd "$REPOD" || exit 1
    "$GIT" -c init.defaultBranch=main init -q .
    "$GIT" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m first
) >/dev/null
GITPATH="$SANDBOX/gitpath"
mkdir -p "$GITPATH"
cp -a "$BARE"/. "$GITPATH/"
ln -sf "$GIT" "$GITPATH/git"
capture env -i HOME="$HOME" PATH="$GITPATH" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; cd '$REPOD' && ga feature >/dev/null && basename \"\$PWD\" && gd -y >/dev/null && basename \"\$PWD\""
assert_status "ga then gd succeeds" 0 "$STATUS"
assert_contains "ga lands in the worktree" "$OUTPUT" "project--feature"
assert_eq "gd leaves no worktree behind" "" "$(ls -d "$SANDBOX/wt/project--feature" 2>/dev/null)"
assert_eq "gd deleted the branch" "" "$("$GIT" -C "$REPOD" branch --list feature)"
capture env -i HOME="$HOME" PATH="$GITPATH" bash --noprofile --norc -c \
    ". '$SHELLDIR/init.sh'; cd '$REPOD' && gd -y"
assert_contains "gd refuses outside a worktree" "$OUTPUT" "is not a <repo>--<branch> worktree"
assert_status "and fails" 1 "$STATUS"

# --- an interactive rc with the user's own aliases ----------------------------
# Interactive bash expands aliases while it parses a sourced file, so the
# fragment has to survive the aliases a real rc defines before the include:
# Omarchy's `alias cd=zd` (a jump function that prints) and its decompress, ga,
# gd and ff aliases, which share names with the functions here.
RC="$SANDBOX/interactive.bashrc"
cat >"$RC" <<EOF
zd() { echo "ZD-JUMPED \$*"; }
alias cd=zd
alias decompress='tar -xzf'
alias ga='git add'
alias gd='git diff'
alias ff='flatpak'
alias ls='ls --my-own-flags'
[ -r "$INCLUDE" ] && . "$INCLUDE"
EOF
FAKE_EZA="$SANDBOX/fake-eza"
mkdir -p "$FAKE_EZA"
cp -a "$GITPATH"/. "$FAKE_EZA/"
printf '#!/bin/sh\nexit 0\n' >"$FAKE_EZA/eza"
chmod +x "$FAKE_EZA/eza"
interactive() { # COMMAND — run it in `bash -i` after the rc above, from $WORK
    capture env -i HOME="$HOME" PATH="$FAKE_EZA" bash --noprofile --rcfile "$RC" -i -c \
        "builtin cd '$WORK' && $1"
}
interactive 'printf "dir=%s\n" "$HASEEN_SHELL_DIR"; for f in decompress ga gd ff tdl _haseen_mux; do declare -F "$f" >/dev/null && printf "%s=function\n" "$f"; done'
assert_status "an aliased rc still sources the fragment" 0 "$STATUS"
assert_not_contains "no syntax error from an alias named like a function" "$OUTPUT" "syntax error"
assert_not_contains "no missing sibling file" "$OUTPUT" "No such file"
assert_not_contains "the user's cd alias never ran" "$OUTPUT" "ZD-JUMPED"
assert_contains "the fragment finds its own directory" "$OUTPUT" "dir=$(builtin cd "$SHELLDIR" && pwd -P)"
# The user's alias still wins at the prompt (their rc, their choice); the
# function is defined underneath it and reachable as \ga.
for fn in decompress ga gd ff tdl _haseen_mux; do
    assert_contains "$fn is defined under the user's aliases" "$OUTPUT" "$fn=function"
done
interactive 'alias ls'
assert_contains "the user's own ls alias wins over haseen's" "$OUTPUT" "ls --my-own-flags"
interactive "builtin cd '$REPOD' && \\ga feature2 >/dev/null && basename \"\$PWD\" && \\gd -y >/dev/null && basename \"\$PWD\""
assert_status "ga then gd work with cd aliased" 0 "$STATUS"
assert_contains "ga moves with the real cd, not the alias" "$OUTPUT" "project--feature2"
assert_not_contains "ga/gd never ran the user's cd alias" "$OUTPUT" "ZD-JUMPED"
assert_eq "gd removed the second worktree" "" "$(ls -d "$SANDBOX/wt/project--feature2" 2>/dev/null)"

# An alias that quietly changes directory and succeeds must not move the
# fragment's notion of where it lives either (it would source $PWD/aliases.sh).
mkdir -p "$WORK/decoy"
echo 'echo DECOY-SOURCED' >"$WORK/decoy/aliases.sh"
cat >"$RC" <<EOF
zd() { builtin cd '$WORK/decoy'; }
alias cd=zd
[ -r "$INCLUDE" ] && . "$INCLUDE"
EOF
interactive 'type -t tdl'
assert_not_contains "a silent cd alias cannot redirect the sources" "$OUTPUT" "DECOY-SOURCED"
assert_contains "and the functions still load" "$OUTPUT" "function"
