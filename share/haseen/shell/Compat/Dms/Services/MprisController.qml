pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// qs.Services.MprisController for DankMaterialShell plugins (architecture
// 5.4): the MPRIS players and the one a media widget should show. Names and
// the choice of activePlayer follow DankMaterialShell's
// quickshell/Services/MprisController.qml (MIT, Copyright (c) 2025 Avenge
// Media LLC), without its pinning, exclusion list and saved identity (DMS
// settings haseen does not have):
//   - a playing player wins, preferring one that can be controlled, and the
//     current one keeps the place while it is still playing;
//   - otherwise the current player stays while it is present and not stopped;
//   - otherwise the first controllable player that is not stopped, or none.
// Everything is driven by MPRIS D-Bus signals; nothing polls.
Singleton {
    id: root

    readonly property string _playerctldBusName: "org.mpris.MediaPlayer2.playerctld"
    readonly property list<MprisPlayer> availablePlayers: Mpris.players.values.filter(p => p.dbusName !== _playerctldBusName)
    property MprisPlayer activePlayer: null

    function isIdle(player: MprisPlayer): bool {
        return player !== null && player.playbackState === MprisPlaybackState.Stopped;
    }

    function setActivePlayer(player: MprisPlayer): void {
        activePlayer = player;
    }

    function _resolveActivePlayer(): void {
        const players = availablePlayers;
        const playing = players.filter(p => p.isPlaying);
        if (playing.length > 0) {
            if (activePlayer && activePlayer.isPlaying && players.indexOf(activePlayer) >= 0)
                return;
            activePlayer = playing.find(p => p.canControl) ?? playing[0];
            return;
        }
        if (activePlayer && players.indexOf(activePlayer) >= 0 && !isIdle(activePlayer))
            return;
        activePlayer = players.find(p => p.canControl && !isIdle(p)) ?? null;
    }

    onAvailablePlayersChanged: _resolveActivePlayer()
    Component.onCompleted: _resolveActivePlayer()

    Instantiator {
        model: root.availablePlayers

        Connections {
            required property MprisPlayer modelData

            target: modelData

            function onPlaybackStateChanged() {
                root._resolveActivePlayer();
            }
        }
    }
}
