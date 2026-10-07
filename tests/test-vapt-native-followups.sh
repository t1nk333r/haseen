# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Pinned metadata cannot bless arbitrary runtimes or host metadata decoys.
source "$FIXTURES/vapt-lib.sh"
native_followup_case() {
    vapt_sandbox "$1"
    vapt_root
    vapt_home_in_root
    vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING"
    STORE="$ROOT$XDG_DATA_HOME/haseen/vapt/pipx"
    mkdir -p "$ROOT${VAPT_LINK%/*}"
    ln -s "$VAPT_FRAGMENT" "$ROOT$VAPT_LINK"
}
native_report() { # LOGICAL SPEC GROUP
    vapt_report_put "$1"$'\t'"$3"$'\tnative\t'"$2"$'\tresolved\talready-exact\texact\tblackarch,native\n# environment\tok\n# mutation-failed\t0'
}
for logical in sherlock pyrit; do
    native_followup_case "vapt-native-external-$logical"
    spec="$(vapt_native_spec "$logical")"
    dist="${spec%%==*}" probe="$logical"
    [[ $logical != pyrit ]] || probe=pyrit_shell
    vapt_native_env "$STORE" "$dist" "$spec" "$probe" "${spec#*==}"
    native_report "$logical" "$spec" osint
    vapt_api status
    assert_status "$logical supported interpreter exact control" 0 "$STATUS"
    # It is executable, named python3.14, and fixture-local, but not the
    # distribution-owned system base or an approved managed uv interpreter.
    mkdir -p "$ROOT/other/runtime"
    _vapt_stub_log "$ROOT/other/runtime/python3.14" native-impostor
    rm "$STORE/venvs/$dist/bin/python"
    ln -s /other/runtime/python3.14 "$STORE/venvs/$dist/bin/python"
    vapt_api status
    assert_status "$logical arbitrary external runtime cannot satisfy exact status" 2 "$STATUS"
    vapt_api install --dry-run --groups "$(if [[ $logical == pyrit ]]; then echo htb-coae; else echo osint; fi)"
    assert_not_contains "$logical runtime rejected before already-exact shortcut" "$(vapt_row "$logical")" $'\talready-exact\t'
    assert_eq "$logical impostor interpreter never executed" '' "$(vapt_calls native-impostor)"
    assert_eq "$logical unproven runtime is preserved, not reconciled" skipped "$(vapt_field "$logical" 6)"
    vapt_tools_untouched "$logical runtime provenance"
done

# A positive exact VCS fixture becomes non-exact after each single nested link.
# Decoys are ordinary scratch files outside ROOT, never real user environments.
for component in pipx_metadata.json lib lib/python3.14 lib/python3.14/site-packages \
    lib/python3.14/site-packages/netexec-1.4.0.dist-info \
    lib/python3.14/site-packages/netexec-1.4.0.dist-info/METADATA \
    lib/python3.14/site-packages/netexec-1.4.0.dist-info/direct_url.json; do
    native_followup_case "vapt-native-metadata-${component//\//-}"
    spec="$(vapt_native_spec netexec)"
    vapt_native_env "$STORE" netexec "$spec" netexec 1.4.0
    native_report netexec "$spec" ad
    vapt_api status
    assert_status "$component exact contained metadata control" 0 "$STATUS"
    venv="$STORE/venvs/netexec"
    decoy="$SANDBOX/host-metadata"
    mv "$venv/$component" "$decoy"
    ln -s "$decoy" "$venv/$component"
    before="$(find "$decoy" -printf '%P %y %m %s %T@ %l\n' | LC_ALL=C sort)"
    vapt_api status
    assert_status "$component host metadata cannot supply exact VCS proof" 2 "$STATUS"
    assert_eq "$component host decoy remains untouched" "$before" "$(find "$decoy" -printf '%P %y %m %s %T@ %l\n' | LC_ALL=C sort)"
    vapt_tools_untouched "$component host decoy"
done
