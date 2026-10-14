# shellcheck shell=bash
# Shared read-only workflow adapter. Python observes metadata, not tools.
# -I keeps the working directory (often a cloned exploit or loot directory),
# PYTHON* variables and user site-packages out of the interpreter.
vapt_workflow() {
    local command="$1"
    shift
    if [[ $command == menu ]]; then
        # The menu guard reads configuration only and imports no inventory code.
        /usr/bin/python3 -I -B "$HASEEN_PATH/layers/vapt/workflow_menu.py" "$@"
    else
        /usr/bin/python3 -I -B "$HASEEN_PATH/layers/vapt/workflow.py" "$command" "$@"
    fi
}

vapt_workflow_status() {
    local command="$1" output rc=0
    shift
    # Preserve the established provisioning verifier and its 0/1/2 meaning.
    output="$(layer_run_status vapt)" || rc=$?
    printf '%s\n' "$output" | VAPT_WORKFLOW_STATUS_CODE="$rc" vapt_workflow "$command" "$@"
}
