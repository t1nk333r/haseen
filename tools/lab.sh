#!/usr/bin/env bash
# tools/lab.sh — run this checkout end to end inside a disposable CachyOS VM.
#
# haseen's own gates are hermetic: tests/run.sh reads tests/fixtures/ through
# HASEEN_SYSROOT and every mutation is stubbed out. Nothing in this repo has
# ever executed a real pkg_install, a real seed into a real $HOME, or a real
# Hyprland reload — that is exactly why plan 014 is blocked ("no end-to-end run
# on a real CachyOS machine or VM yet", handoff.md). This wrapper is the rig
# for it.
#
# It drives the owner's own t1nk33r-lab (github.com/t1nk333r/t1nk33r-lab, MIT):
# a disposable VM with a golden snapshot, `reset` in seconds and a non-
# interactive interface. This file only
#   1. reports which of the lab's prerequisites this machine is missing,
#   2. points the lab at a CachyOS image and at this checkout,
#   3. installs haseen in the guest and runs tests/run.sh there,
# and it is a no-op dry run until you pass --yes.
#
# The lab checkout never lands inside this repo (it carries multi-GB images):
# it goes to $HASEEN_LAB_DIR, default ~/.cache/haseen/lab.
#
# Nothing here needs sudo on the host. The only privileged command is
# `install.sh` *inside* the guest, where the lab's cidata user has passwordless
# sudo by construction.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../share/haseen/lib/common.sh
source "$REPO/share/haseen/lib/common.sh"

LAB_REPO_URL=${LAB_REPO_URL:-https://github.com/t1nk333r/t1nk33r-lab.git}
HASEEN_LAB_DIR=${HASEEN_LAB_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/haseen/lab}

# The CachyOS desktop ISO, pinned by date. The lab's cachyos arm builds the
# URL itself from LAB_CACHYOS_RELEASE (lab.conf) and verifies it against the
# .sha256 next to it.
CACHYOS_DATE=${CACHYOS_DATE:-260809}

# The guest's own name and port, so this never collides with a lab checkout the
# owner is already driving by hand.
LAB_NAME=${LAB_NAME:-haseen-lab}
LAB_SSH_PORT=${LAB_SSH_PORT:-2242}
# haseen's installer needs a package mirror, so the guest cannot be isolated.
# That is a conscious step down from the lab's default; the README spells out
# what it re-exposes.
LAB_NET=${LAB_NET:-internet}

GUEST_DIR=${GUEST_DIR:-haseen}

usage() {
    cat <<EOF
Usage: tools/lab.sh [--dry-run] [--yes] [--help]

Checks the prerequisites for a disposable CachyOS VM, then installs this
checkout into one and runs tests/run.sh inside it.

  --dry-run   print the plan and change nothing (the default)
  --yes       actually do it
  --help      this text

Environment:
  HASEEN_LAB_DIR   where the lab checkout lives   (default ~/.cache/haseen/lab)
  LAB_REPO_URL     the lab's git remote
  CACHYOS_DATE     the pinned CachyOS ISO date    (default $CACHYOS_DATE)
  (the ISO URL itself: LAB_CACHYOS_ISO_URL in the lab's lab.conf)
  LAB_NAME         guest/container name           (default haseen-lab)
  LAB_SSH_PORT     qemu hostfwd port in the container (default 2242)
  LAB_NET          isolated|internet              (default internet)
EOF
}

# --- the prerequisite report -------------------------------------------------
# Every check prints one line. BLOCKERS collects the ones that stop the run,
# each with the remedy, so a failure says what to do and not just what broke.
BLOCKERS=()

check_ok() { printf '  ok      %s\n' "$*"; }
check_bad() {
    printf '  MISSING %s\n' "$1"
    BLOCKERS+=("$2")
}
check_warn() { printf '  warn    %s\n' "$*"; }

# have_qemu — a QEMU the lab can actually start a guest with. The lab does not
# install a hypervisor on the host: runner/Dockerfile carries qemu, OVMF and
# genisoimage, and /dev/kvm is passed into that container (README "How it
# works"). So the question is not "is qemu-system-x86_64 in PATH" but "is
# there a container engine holding one, or failing that a host binary".
QEMU_WHERE=""
have_qemu() {
    if docker info >/dev/null 2>&1; then
        QEMU_WHERE="docker (the lab builds runner/Dockerfile, which carries qemu + OVMF)"
        return 0
    fi
    if have qemu-system-x86_64; then
        QEMU_WHERE="host $(command -v qemu-system-x86_64) (the lab still wants docker for its runner)"
        return 0
    fi
    return 1
}

report() {
    echo "Prerequisites for a CachyOS lab guest:"

    if [[ -d $HASEEN_LAB_DIR/.git ]]; then
        check_ok "lab checkout       $HASEEN_LAB_DIR"
    else
        check_warn "lab checkout       absent; would clone $LAB_REPO_URL into $HASEEN_LAB_DIR"
    fi

    if [[ -c /dev/kvm && -w /dev/kvm ]]; then
        check_ok "/dev/kvm           writable by $(id -un)"
    else
        check_bad "/dev/kvm           not present or not writable by $(id -un)" \
            "load the kvm module and give your user write access to /dev/kvm"
    fi

    if have_qemu; then
        check_ok "qemu               $QEMU_WHERE"
    else
        local why="no container engine (docker info fails)"
        have docker && why="docker is installed but its daemon is unreachable (docker info fails)"
        check_bad "qemu               $why, and no qemu-system-x86_64 on this host" \
            "give this user docker access (the lab runs qemu inside runner/Dockerfile), or install qemu"
    fi

    # The lab's own doctor list, verbatim (t1nk33r-lab/lab cmd_doctor).
    local tool missing=()
    for tool in ssh ssh-keygen curl openssl jq tar sha256sum timedatectl; do
        have "$tool" || missing+=("$tool")
    done
    if ((${#missing[@]} == 0)); then
        check_ok "host tools         ssh ssh-keygen curl openssl jq tar sha256sum timedatectl"
    else
        check_bad "host tools         ${missing[*]}" "install: ${missing[*]}"
    fi

    local avail
    avail="$(df --output=avail -BG "$(dirname "$HASEEN_LAB_DIR")" 2>/dev/null | tail -1 | tr -dc 0-9)"
    avail=${avail:-0}
    if ((avail >= 70)); then
        check_ok "disk               ${avail}G free under $(dirname "$HASEEN_LAB_DIR")"
    else
        check_warn "disk               only ${avail}G free under $(dirname "$HASEEN_LAB_DIR"); the ISO plus the golden and overlay disks want ~70G"
    fi

    if [[ -r $HASEEN_LAB_DIR/lab ]] && grep -qE '^[[:space:]]*cachyos\)' "$HASEEN_LAB_DIR/lab"; then
        check_ok "guest mode         LAB_DISTRO=cachyos is supported by the lab"
    else
        check_bad "guest mode         the lab checkout has no LAB_DISTRO=cachyos arm" \
            "update $HASEEN_LAB_DIR from $LAB_REPO_URL"
    fi
    if [[ -r $HASEEN_LAB_DIR/lab ]] && grep -q 'LAB_SECUREBOOT' "$HASEEN_LAB_DIR/lab"; then
        check_ok "firmware           LAB_SECUREBOOT=on (OVMF secboot, Setup Mode)"
    else
        check_bad "firmware           the lab checkout has no LAB_SECUREBOOT knob" \
            "update $HASEEN_LAB_DIR from $LAB_REPO_URL"
    fi

    echo
    echo "Guest it would build:"
    printf '  %-18s %s\n' "image" "CachyOS desktop ISO $CACHYOS_DATE"
    printf '  %-18s %s\n' "checkout" "$REPO -> ~/$GUEST_DIR in the guest"
    printf '  %-18s %s\n' "name/port/net" "$LAB_NAME / $LAB_SSH_PORT / $LAB_NET"
    echo
}

# --- the run ----------------------------------------------------------------
lab() { run env -C "$HASEEN_LAB_DIR" \
    LAB_NAME="$LAB_NAME" LAB_DISTRO=cachyos LAB_CACHYOS_RELEASE="$CACHYOS_DATE" \
    LAB_SSH_PORT="$LAB_SSH_PORT" LAB_NET="$LAB_NET" LAB_SECUREBOOT=on \
    ./lab "$@"; }

plan() {
    [[ -d $HASEEN_LAB_DIR/.git ]] ||
        run git clone --depth 1 "$LAB_REPO_URL" "$HASEEN_LAB_DIR"

    # bootstrap builds the runner, fetches and verifies the ISO and seals a
    # golden; reset is the cheap path once that exists.
    if [[ -f $HASEEN_LAB_DIR/images/golden.qcow2 ]]; then
        lab reset
    else
        lab bootstrap
    fi

    # Push this checkout in. Not `lab sync`: that mirrors $HOME dotfiles, which
    # is the opposite direction and would carry the owner's real config into a
    # disposable VM.
    if $DRY_RUN; then
        echo "DRYRUN: tar -C $REPO --exclude=.git --exclude=tests/.out -cf - . | lab ssh 'rm -rf ~/$GUEST_DIR && mkdir -p ~/$GUEST_DIR && tar -C ~/$GUEST_DIR -xf -'"
    else
        tar -C "$REPO" --exclude=.git --exclude=tests/.out -cf - . |
            lab ssh "rm -rf ~/$GUEST_DIR && mkdir -p ~/$GUEST_DIR && tar -C ~/$GUEST_DIR -xf -"
    fi

    # install.sh refuses root (require_not_root) and escalates itself through
    # common.sh; the guest user's sudo is what it uses there. The default layer
    # set plus secureboot: desktop's packages.txt expects omarchy-repo (herdr,
    # ttfx prebuilt), so a list without it measures an AUR fallback instead.
    lab ssh "cd ~/$GUEST_DIR && ./install.sh --yes --layers base,chaotic,omarchy-repo,desktop,theme,shell,secureboot"
    lab ssh "cd ~/$GUEST_DIR && tests/run.sh"
    # Evidence a machine can read: a green suite says nothing about whether the
    # bar came up.
    lab shot haseen-after
}

main() {
    parse_common_flags "$@"
    set -- "${REST[@]}"
    (($# == 0)) || {
        usage >&2
        exit 2
    }
    require_not_root
    # --yes is what runs it; without it this stays a report plus a plan.
    $ASSUME_YES || DRY_RUN=true

    report
    if ((${#BLOCKERS[@]})); then
        printf 'Blocked:\n'
        printf '  - %s\n' "${BLOCKERS[@]}"
        echo
        have_qemu ||
            die "qemu is unavailable: the lab runs it inside a container and docker is unreachable here, and there is no qemu-system-x86_64 on this host either, so no guest can be started."
        die "the prerequisites above are not met; nothing was run"
    fi

    echo "Plan:"
    plan
}

main "$@"
