#!/usr/bin/env bash
# tools/lint.sh — the static gate. Run before every commit, with tests/run.sh.
#   bash -n + shellcheck --severity=warning -x  over every shell file
#   luac -p                                     over every Lua file (Hyprland)
#   qmllint (if present)                        over the Quickshell shell
#   jq empty                                    over every JSON file
# SHELLCHECK / QMLLINT env vars override the binaries (CI pins versions).
set -Eeuo pipefail
cd "$(dirname "$0")/.."

SHELLCHECK=${SHELLCHECK:-shellcheck}
QMLLINT=${QMLLINT:-$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)}
fail=0

mapfile -t sh_files < <(
    {
        printf '%s\n' install.sh tools/*.sh tests/*.sh
        find bin -type f
        find share/haseen -type f \( -name '*.sh' -o -path '*/bin/*' \)
    } | sort -u | while read -r f; do
        [[ -f $f ]] || continue
        head -n1 "$f" | grep -qE '^#!.*(ba)?sh|shellcheck shell=' && echo "$f"
        [[ $f == *.sh ]] && ! head -n1 "$f" | grep -qE '^#!.*(ba)?sh|shellcheck shell=' && echo "$f"
    done | sort -u
)

for f in "${sh_files[@]}"; do
    bash -n "$f" || { echo "bash -n: $f" >&2; fail=1; }
done
"$SHELLCHECK" --severity=warning -x "${sh_files[@]}" || fail=1
echo "shell: ${#sh_files[@]} files"

mapfile -t lua_files < <(find share/haseen -name '*.lua' 2>/dev/null)
for f in "${lua_files[@]}"; do
    luac -p "$f" || fail=1
done
echo "lua: ${#lua_files[@]} files"

mapfile -t json_files < <(find share/haseen tests/fixtures -name '*.json' 2>/dev/null)
for f in "${json_files[@]}"; do
    jq empty "$f" 2>/dev/null || { echo "json: $f" >&2; fail=1; }
done
echo "json: ${#json_files[@]} files"

if [[ -x $QMLLINT && -d share/haseen/shell ]]; then
    mapfile -t qml_files < <(find share/haseen/shell -name '*.qml')
    if ((${#qml_files[@]} > 0)); then
        # Quickshell types are not visible to qmllint without a generated
        # module index; syntax errors still fail, unresolved imports do not.
        out="$("$QMLLINT" --import warning --unqualified disable --missing-property disable \
            --unresolved-type disable "${qml_files[@]}" 2>&1)" || true
        if grep -q 'Error:' <<<"$out"; then
            grep 'Error:' <<<"$out" >&2
            fail=1
        fi
        echo "qml: ${#qml_files[@]} files"
    fi
fi

((fail == 0)) && echo "lint OK"
exit "$fail"
