import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth
import "../../services"
import "../../theme"
import "../notifications"
import "../launcher"

// The centrepiece surface the plan calls for: one place for the toggles
// and sliders that would otherwise need N separate bar icons the 26px bar
// has no room for. Structural template is VolumePopup.qml's own
// (PopupWindow, anchor.item/edges/gravity/adjustment, HoverHandler-driven
// auto-close, grabFocus: false) -- no new popup architecture invented.
//
// Every icon here is outline-at-rest / filled-when-active, per the design
// system -- codepoints hand-verified against nerd-fonts' real
// glyphnames.json this session (not just carried over from memory), after
// finding Bluetooth.qml's own long-standing "md-bluetooth_outline" comment
// pointed at the wrong glyph entirely (md-bell_outline, by coincidence
// still a renderable icon rather than a hard error, which is exactly why
// it went unnoticed).
PopupWindow {
    id: root

    property var anchorItem: null
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: Theme.spacing.qsPanelWidth
    implicitHeight: content.implicitHeight + Theme.spacing.qsPanelPadY * 2

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: if (!hover.hovered)
            root.visible = false
    }
    onVisibleChanged: if (visible)
        closeTimer.stop()

    // Acquires the base polling tier for as long as the panel exists (it's
    // mounted once from QuickSettings.qml's bar icon, never torn down) --
    // the footer's temp/CPU/RAM line needs live data regardless of whether
    // the wallpaper happens to be running its own acquire() right now.
    Component.onCompleted: SystemStats.acquire()
    Component.onDestruction: SystemStats.release()

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.sink, root.source].filter(o => o !== null && o !== undefined)
    }

    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter?.state === BluetoothAdapterState.Enabled
    readonly property bool micMuted: root.source?.audio?.muted ?? false

    // Caffeine via a held systemd-inhibit lock (released by SIGTERM-ing the
    // job) rather than Quickshell.Wayland's native IdleInhibitor -- that API
    // needs a real, currently-mapped Wayland surface to attach to (the
    // wlr-idle-inhibit protocol binds to a wl_surface, not an arbitrary
    // QObject), which none of this panel's own transient popup windows
    // reliably are. systemd-inhibit is the same mechanism most idle
    // daemons (swayidle/hypridle) already respect, sidesteps the surface
    // question entirely, and reuses JobRunner's existing run/cancel pair
    // instead of a second process-lifecycle mechanism.
    property int _caffeineJobId: -1
    readonly property bool caffeineOn: root._caffeineJobId >= 0
    function toggleCaffeine() {
        if (root.caffeineOn) {
            JobRunner.cancel(root._caffeineJobId);
            root._caffeineJobId = -1;
        } else {
            root._caffeineJobId = JobRunner.run("Caffeine (keep awake)", ["systemd-inhibit", "--what=idle:sleep", "--who=quickshell", "--why=user caffeine toggle", "--mode=block", "sleep", "infinity"], { privileged: false });
        }
    }

    readonly property var profileCycle: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    function cyclePowerProfile() {
        const idx = root.profileCycle.indexOf(PowerProfiles.profile);
        PowerProfiles.profile = root.profileCycle[(idx + 1) % root.profileCycle.length];
    }
    readonly property string profileGlyph: PowerProfiles.profile === PowerProfile.Performance ? "\u{F04C5}" // md-speedometer
        : PowerProfiles.profile === PowerProfile.PowerSaver ? "\u{F0F86}" // md-speedometer_slow
        : "\u{F0F85}" // md-speedometer_medium
    readonly property string profileLabel: PowerProfiles.profile === PowerProfile.Performance ? "Performance" : PowerProfiles.profile === PowerProfile.PowerSaver ? "Power Saver" : "Balanced"

    readonly property var activePlayer: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) ?? Mpris.players.values[0] ?? null

    FileView {
        id: maxBrightnessFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
    }
    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        watchChanges: true
    }
    readonly property int maxBrightness: parseInt(maxBrightnessFile.text()) || 100
    readonly property real brightnessFrac: (parseInt(brightnessFile.text()) || 0) / root.maxBrightness

    Timer {
        id: brightnessDebounce
        interval: 40
        property real pending: 0
        onTriggered: Quickshell.execDetached(["brightnessctl", "set", `${Math.round(pending * 100)}%`])
    }
    function setBrightness(frac) {
        brightnessDebounce.pending = frac;
        brightnessDebounce.restart();
    }

    component ToggleTile: Rectangle {
        id: tile
        required property string glyph
        required property string label
        required property bool active
        signal activated

        width: Theme.spacing.qsTileSize
        height: Theme.spacing.qsTileSize
        radius: Theme.spacing.qsTileRadius
        color: tile.active ? Theme.color.launcherTabActiveBg : (tileMouse.containsMouse ? ThemeDefaults.alpha(Theme.base16.base02, 0.6) : ThemeDefaults.alpha(Theme.base16.base02, 0.35))
        border.width: Theme.spacing.borderHairline
        border.color: tile.active ? Theme.color.accentPurple : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
        }

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.glyph
                renderType: Text.NativeRendering
                font.family: Theme.font.family
                font.pixelSize: Theme.spacing.qsTileIconSize
                color: tile.active ? Theme.color.launcherTabActiveFg : Theme.color.fg
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                color: tile.active ? Theme.color.launcherTabActiveFg : Theme.color.launcherPlaceholderFg
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }

    component SliderRow: Row {
        id: sliderRow
        required property string glyph
        required property real value // 0..1
        signal changed(real v)
        signal glyphActivated

        width: parent.width
        spacing: 8
        height: Theme.spacing.qsSliderHeight

        Text {
            width: Theme.spacing.qsSliderIconWidth
            anchors.verticalCenter: parent.verticalCenter
            text: sliderRow.glyph
            renderType: Text.NativeRendering
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
            // One accent colour throughout, muted or not -- the glyph
            // itself already switches shape (volume_mute vs volume_high,
            // microphone_off vs microphone) to signal the muted state, so
            // recolouring the icon pink on top of that read as an
            // inconsistent purple/pink mix across the three stacked
            // sliders rather than a clearer signal.
            color: Theme.color.accentPurple

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sliderRow.glyphActivated()
            }
        }

        Item {
            width: parent.width - Theme.spacing.qsSliderIconWidth - sliderRow.spacing
            height: Theme.spacing.qsSliderHeight
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: Theme.radius.sliderTrack
                color: Theme.color.sliderTrackBg
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.min(1, Math.max(0, sliderRow.value))
                height: 6
                radius: Theme.radius.sliderTrack
                color: Theme.color.accentPurple
            }
            MouseArea {
                anchors.fill: parent

                function setFromX(x) {
                    sliderRow.changed(Math.max(0, Math.min(1, x / width)));
                }
                onPressed: mouse => setFromX(mouse.x)
                onPositionChanged: mouse => {
                    if (pressed)
                        setFromX(mouse.x);
                }
            }
        }
    }

    component SectionLabel: Text {
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
        font.bold: true
        color: Theme.color.launcherPlaceholderFg
    }

    // Hairline section separator -- the panel now carries a header, a
    // toggle grid, sliders, an optional media card, and a footer, so a
    // consistent divider between each does more for "easy to scan" than
    // spacing alone would (spacing alone reads as one undifferentiated
    // block once there are this many sections).
    component Divider: Rectangle {
        width: parent.width
        height: 1
        color: Theme.color.launcherBorder
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.launcherBg
        border.color: Theme.color.launcherBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.panel

        // Swallows clicks so dragging a slider doesn't fall through to
        // anything behind the panel.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.qsPanelPadX
            }
            topPadding: Theme.spacing.qsPanelPadY
            bottomPadding: Theme.spacing.qsPanelPadY
            spacing: Theme.spacing.qsSectionGap

            Text {
                text: "QUICK SETTINGS"
                color: Theme.color.accentPurple
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                font.bold: true
            }

            Grid {
                width: parent.width
                columns: 3
                rowSpacing: Theme.spacing.qsTileGap
                columnSpacing: Theme.spacing.qsTileGap

                ToggleTile {
                    glyph: root.wifiOn ? "\u{F05A9}" : "\u{F05AA}" // md-wifi / md-wifi_off
                    label: "Wi-Fi"
                    active: root.wifiOn
                    onActivated: Networking.wifiEnabled = !Networking.wifiEnabled
                }
                ToggleTile {
                    glyph: root.btOn ? "\u{F00AF}" : "\u{F00B2}" // md-bluetooth / md-bluetooth_off
                    label: "Bluetooth"
                    active: root.btOn
                    onActivated: if (root.btAdapter)
                        root.btAdapter.enabled = !root.btAdapter.enabled
                }
                ToggleTile {
                    glyph: NotificationState.dnd ? "\u{F009B}" : "\u{F009C}" // md-bell_off / md-bell_outline
                    label: "DND"
                    active: NotificationState.dnd
                    onActivated: NotificationState.toggleDnd()
                }
                ToggleTile {
                    glyph: root.caffeineOn ? "\u{F0176}" : "\u{F06CA}" // md-coffee / md-coffee_outline
                    label: "Caffeine"
                    active: root.caffeineOn
                    onActivated: root.toggleCaffeine()
                }
                ToggleTile {
                    glyph: root.micMuted ? "\u{F036D}" : "\u{F036E}" // md-microphone_off / md-microphone_outline
                    label: "Mic"
                    active: root.micMuted
                    onActivated: if (root.source)
                        root.source.audio.muted = !root.source.audio.muted
                }
                ToggleTile {
                    glyph: root.profileGlyph
                    label: root.profileLabel
                    active: PowerProfiles.profile !== PowerProfile.Balanced
                    onActivated: root.cyclePowerProfile()
                }
            }

            Divider {}

            Column {
                width: parent.width
                spacing: Theme.spacing.qsSliderRowGap

                SliderRow {
                    glyph: (root.sink?.audio?.muted ?? false) ? "\u{F075F}" : "\u{F057E}" // md-volume_mute / md-volume_high
                    value: root.sink?.audio?.volume ?? 0
                    onChanged: v => {
                        if (root.sink)
                            root.sink.audio.volume = v;
                    }
                    onGlyphActivated: if (root.sink)
                        root.sink.audio.muted = !root.sink.audio.muted
                }
                SliderRow {
                    glyph: root.micMuted ? "\u{F036D}" : "\u{F036C}" // md-microphone_off / md-microphone
                    value: root.source?.audio?.volume ?? 0
                    onChanged: v => {
                        if (root.source)
                            root.source.audio.volume = v;
                    }
                    onGlyphActivated: if (root.source)
                        root.source.audio.muted = !root.source.audio.muted
                }
                SliderRow {
                    glyph: "\u{F00DF}" // md-brightness_6
                    value: root.brightnessFrac
                    onChanged: v => root.setBrightness(v)
                }
            }

            // Media card -- only present when a player exists, so the panel
            // doesn't waste a permanent slot on a mostly-empty state.
            Rectangle {
                width: parent.width
                visible: root.activePlayer !== null
                height: visible ? mediaRow.implicitHeight + Theme.spacing.qsMediaGap * 2 : 0
                radius: Theme.radius.input
                color: ThemeDefaults.alpha(Theme.base16.base02, 0.35)

                Row {
                    id: mediaRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Theme.spacing.qsMediaGap
                    }
                    spacing: Theme.spacing.qsMediaGap

                    Rectangle {
                        width: Theme.spacing.qsMediaArtSize
                        height: Theme.spacing.qsMediaArtSize
                        radius: Theme.radius.input
                        color: ThemeDefaults.alpha(Theme.base16.base03, 0.6)
                        Text {
                            anchors.centerIn: parent
                            text: "\u{F0387}" // md-music_note
                            renderType: Text.NativeRendering
                            font.family: Theme.font.family
                            font.pixelSize: Theme.spacing.qsTileIconSize
                            color: Theme.color.launcherPlaceholderFg
                        }
                    }

                    Column {
                        width: mediaRow.width - Theme.spacing.qsMediaArtSize - Theme.spacing.qsMediaGap * 3 - 66
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.activePlayer?.trackTitle ?? ""
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.activePlayer?.trackArtist ?? ""
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            text: "\u{F04AE}" // md-skip_previous
                            renderType: Text.NativeRendering
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                            color: (root.activePlayer?.canGoPrevious ?? false) ? Theme.color.fg : Theme.color.moduleDisabledFg
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.activePlayer?.previous() }
                        }
                        Text {
                            text: (root.activePlayer?.isPlaying ?? false) ? "\u{F03E4}" : "\u{F040A}" // md-pause / md-play
                            renderType: Text.NativeRendering
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                            color: Theme.color.accentPurple
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.activePlayer?.togglePlaying() }
                        }
                        Text {
                            text: "\u{F04AD}" // md-skip_next
                            renderType: Text.NativeRendering
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                            color: (root.activePlayer?.canGoNext ?? false) ? Theme.color.fg : Theme.color.moduleDisabledFg
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.activePlayer?.next() }
                        }
                    }
                }
            }

            Divider {}

            Column {
                width: parent.width
                spacing: 4

                // Plain text, not a graph -- this is the landing spot for
                // the temp/CPU/RAM numbers NetSpeed/ResourceGraph/
                // Temperature used to show directly in the bar (all three
                // were cut when the bar was trimmed from thirteen modules
                // down to seven). A number here answers "where did that
                // go"; a sparkline here would just reintroduce the same
                // visual noise one level down. Monitor still has the real
                // graphs for anyone who wants history, not just a snapshot.
                Text {
                    text: `${SystemStats.tempC.toFixed(0)}°C  ·  ${SystemStats.cpuPercent.toFixed(0)}% CPU  ·  ${(SystemStats.memUsedFrac * 100).toFixed(0)}% RAM`
                    color: SystemStats.tempCritical ? Theme.color.critical : Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacing.qsFooterGap

                    Text {
                        text: `up ${SystemStats.uptimeText}`
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    Text {
                        visible: JobRunner.runningCount > 0
                        text: `${JobRunner.runningCount} job${JobRunner.runningCount === 1 ? "" : "s"} running`
                        color: Theme.color.accentPurple
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                LauncherState.visible = true;
                                LauncherState.setTab("system");
                                SystemState.activeSection = "jobs";
                                root.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
