#!/usr/bin/env bash
# haseen.privacy location watcher: GeoClue's Manager.InUse, event-driven.
# Prints "unavailable" and exits when GeoClue is not installed. Otherwise
# prints the current InUse (only if GeoClue already runs: a Get on an absent
# name would D-Bus-activate it) and then becomes `gdbus monitor`, which
# watches the name without activating it and prints every PropertiesChanged.
# Widget.qml parses the lines with Privacy.js parseGeoclue().
#
# GeoClue does not expose which app asked: its Client objects belong to the
# requesting peer, so the tooltip says "Location" without a name.
set -uo pipefail

name=org.freedesktop.GeoClue2
bus=(--system --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus)

if ! gdbus call "${bus[@]}" --method org.freedesktop.DBus.ListActivatableNames 2>/dev/null | grep -q "'$name'"; then
    echo unavailable
    exit 0
fi

if gdbus call "${bus[@]}" --method org.freedesktop.DBus.NameHasOwner "$name" 2>/dev/null | grep -q true; then
    in_use=$(gdbus call --system --dest "$name" --object-path /org/freedesktop/GeoClue2/Manager \
        --method org.freedesktop.DBus.Properties.Get org.freedesktop.GeoClue2.Manager InUse 2>/dev/null)
    [[ $in_use == *true* ]] && echo "'InUse': <true>" || echo "'InUse': <false>"
fi

exec gdbus monitor --system --dest "$name" --object-path /org/freedesktop/GeoClue2/Manager
