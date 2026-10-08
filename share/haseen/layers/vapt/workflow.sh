# shellcheck shell=bash
# Shared read-only workflow adapter. Python observes metadata, not tools.
vapt_workflow() {
    local command="$1"
    shift
    /usr/bin/python3 -B "$HASEEN_PATH/layers/vapt/workflow.py" "$command" "$@"
}

vapt_workflow_status() {
    local command="$1" output rc=0
    shift
    # Preserve the established provisioning verifier and its 0/1/2 meaning.
    output="$(layer_run_status vapt)" || rc=$?
    printf '%s\n' "$output" | VAPT_WORKFLOW_STATUS_CODE="$rc" vapt_workflow "$command" "$@"
}
