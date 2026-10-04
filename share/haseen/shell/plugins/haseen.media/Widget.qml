import QtQuick
import Quickshell.Services.Mpris
import qs.Haseen
import qs.Haseen.Widgets
import "Media.js" as Media

// Now playing over MPRIS (Quickshell.Services.Mpris, D-Bus signals only).
// Shows the playing player, else a paused one; takes no room without a
// player. Click toggles play/pause, wheel up/down = previous/next. In a
// vertical bar only the play/pause glyph shows.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: {
        const i = Media.pickIndex(players.map(p => ({
                    isPlaying: p.isPlaying,
                    stopped: p.playbackState === MprisPlaybackState.Stopped
                })));
        return i >= 0 ? players[i] : null;
    }
    readonly property string full: player ? Media.label(player.trackTitle, player.trackArtist, player.identity, settings.showArtist !== false) : ""

    glyph: player && player.isPlaying ? "\uf04c" : "\uf04b"
    text: vertical ? "" : Media.truncate(full, typeof settings.maxLength === "number" ? settings.maxLength : 40)
    color: player && player.isPlaying ? Theme.barForeground : Theme.muted
    implicitWidth: player ? contentWidth : 0

    onClicked: button => {
        if (player && button === Qt.LeftButton && player.canTogglePlaying)
            player.togglePlaying();
    }
    onScrolled: steps => {
        if (!player)
            return;
        if (steps > 0 && player.canGoPrevious)
            player.previous();
        else if (steps < 0 && player.canGoNext)
            player.next();
    }
}
