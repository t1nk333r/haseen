#!/usr/bin/env bash
# haseen.sysusage GPU probe. Read-only; run once by Sampler.qml when the
# widget first shows. Prints one line per DRM card:
#   <card> <driver> <boot_vga 0|1> <method> [args...]
# method (parsed by Usage.js parseGpus):
#   busy PATH      amdgpu gpu_busy_percent
#   nvidia SLOT    nvidia-smi stream for that PCI slot
#   rc6 PATH       Intel idle-residency counter in ms (i915 rc6, xe gtidle):
#                  busy = 1 - idle/wall. Needs no root, unlike the i915 PMU
#                  (perf_event_paranoid) that intel_gpu_top uses.
#   freq ACT MAX   Intel clock ratio, shown as "GPU freq" (no residency file)
#   none           no unprivileged source
# $1 is a sysfs root prefix for tests (default: the live /).
set -uo pipefail

root=${1:-}

for d in "$root"/sys/class/drm/card[0-9]*; do
    card=${d##*/}
    # Connectors (card1-eDP-1) live in the same directory.
    [[ $card == *-* || ! -r $d/device/uevent ]] && continue
    drv=$(sed -n 's/^DRIVER=//p' "$d/device/uevent")
    slot=$(sed -n 's/^PCI_SLOT_NAME=//p' "$d/device/uevent")
    vga=$(cat "$d/device/boot_vga" 2>/dev/null) || vga=0
    method=none
    case $drv in
    amdgpu)
        [[ -r $d/device/gpu_busy_percent ]] && method="busy $d/device/gpu_busy_percent"
        ;;
    nvidia)
        [[ -n $slot ]] && command -v nvidia-smi >/dev/null && method="nvidia $slot"
        ;;
    i915 | xe)
        for f in "$d/gt/gt0/rc6_residency_ms" "$d/power/rc6_residency_ms" "$d/device/tile0/gt0/gtidle/idle_residency_ms"; do
            if cat "$f" >/dev/null 2>&1; then
                method="rc6 $f"
                break
            fi
        done
        if [[ $method == none ]]; then
            for pair in "$d/gt_act_freq_mhz $d/gt_max_freq_mhz" "$d/device/tile0/gt0/freq0/act_freq $d/device/tile0/gt0/freq0/max_freq"; do
                read -r act max <<<"$pair"
                if [[ -r $act && -r $max ]]; then
                    method="freq $act $max"
                    break
                fi
            done
        fi
        ;;
    esac
    printf '%s %s %s %s\n' "$card" "${drv:-unknown}" "${vga:-0}" "$method"
done
