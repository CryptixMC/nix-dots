import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../theme"
import "../wallpaper"

// The lock surface itself — `WlSessionLock.surface` instantiates one of
// these per screen automatically (ext-session-lock-v1 semantics), so this
// stays a plain Item, not a PanelWindow: WlSessionLockSurface is the
// window, this is just its contentItem's root.
//
// Background is the same live WallpaperContent the desktop uses (see
// quickshell/modules/wallpaper/WallpaperContent.qml) — not the flat themed
// colour this file used before that component existed. shouldAnimate is
// unconditionally true here: Wallpaper.qml's per-monitor "pause behind a
// fullscreen window" concern doesn't apply to a lock surface (nothing else
// is on screen to be fullscreen behind), and this is the one thing visible.
//
// No Escape-to-close handler anywhere in this file — unlike every other
// overlay in this repo (Launcher, Chat, popups), a lock screen must not be
// dismissible without successful authentication.
Item {
    id: root

    required property var lockSurface

    anchors.fill: parent

    WallpaperContent {
        anchors.fill: parent
        wp: Theme.wallpaper
        shouldAnimate: true
        // A scene's own system-stats HUD lives in the same left corner
        // this file's Column does -- see Orbital.qml's showHud comment.
        showSceneHud: false
    }

    // Live host + uptime, matching lock.html's "HOST"/"UPTIME" pairs.
    // Uptime is read once and ticked forward from Date.now() deltas rather
    // than re-read every second — /proc/uptime's inotify/poll behaviour
    // under FileView.watchChanges isn't something to depend on for a
    // once-a-second display, and a wall-clock delta is exact regardless.
    property string hostname: ""
    property real uptimeBaseSeconds: 0
    property real uptimeBaseMs: 0
    property string uptimeText: "T+ 00:00:00"

    function formatUptime(totalSeconds) {
        const s = Math.max(0, Math.floor(totalSeconds));
        const pad = n => String(n).padStart(2, "0");
        return `T+ ${pad(Math.floor(s / 3600))}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}`;
    }

    FileView {
        path: "/etc/hostname"
        onLoaded: root.hostname = text().trim().toUpperCase()
        printErrors: false
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: {
            const secs = parseFloat(text().split(" ")[0]);
            if (!isNaN(secs)) {
                root.uptimeBaseSeconds = secs;
                root.uptimeBaseMs = Date.now();
                root.uptimeText = root.formatUptime(secs);
            }
        }
        printErrors: false
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.uptimeText = root.formatUptime(root.uptimeBaseSeconds + (Date.now() - root.uptimeBaseMs) / 1000)
    }

    // Left-aligned content block, matching lock.html — the previous
    // centered Column read like a generic dialog box; the design puts the
    // whole read (clock, host, uptime, password) as one left-anchored
    // column against the wallpaper, the same way the plate's own readouts
    // sit in its corners.
    Column {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 96
        }
        spacing: 10

        Text {
            text: Qt.formatDateTime(new Date(), "h:mm")
            color: Theme.color.textStrong
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeDisplay
            font.bold: true

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: parent.text = Qt.formatDateTime(new Date(), "h:mm")
            }
        }

        Row {
            spacing: 24

            Row {
                spacing: 8
                Text {
                    text: "UPTIME"
                    color: Theme.color.textDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }
                Text {
                    text: root.uptimeText
                    color: Theme.color.textLabel
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }
            }

            Row {
                spacing: 8
                Text {
                    text: "HOST"
                    color: Theme.color.textDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }
                Text {
                    text: root.hostname.length > 0 ? `[ ${root.hostname} ]` : ""
                    color: Theme.color.textLabel
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }
            }
        }

        Item { width: 1; height: 16 } // breathing room before the field, matches lock.html's gap

        Text {
            // The PAM conversation's own message once one is in flight
            // (usually just "Password:"), falling back to a static label
            // before lock() has ever been called -- LockService starts in
            // phaseIdle with an empty prompt.
            text: LockService.phase === LockService.phaseFailed ? LockService.errorMessage : (LockService.prompt.length > 0 ? LockService.prompt : "Password:")
            // critical on failure -- colour only, no shake. Matches the
            // ruling already applied everywhere else in this restyle
            // (lock.html's own footer note: "no shake — critical is colour
            // only").
            color: LockService.phase === LockService.phaseFailed ? Theme.color.critical : Theme.color.textBody
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
        }

        Rectangle {
            width: Theme.spacing.launcherWidth
            height: Theme.spacing.launcherInputHeight
            radius: Theme.radius.input
            color: Theme.color.ground
            border.width: (passwordInput.activeFocus || LockService.phase === LockService.phaseFailed) ? Theme.spacing.borderCard : Theme.spacing.borderHairline
            border.color: LockService.phase === LockService.phaseFailed ? Theme.color.critical : (passwordInput.activeFocus ? Theme.color.focus : Theme.color.line)

            Text {
                // nf-fa-lock (U+F023) -- screenshotted against this exact
                // font before use; the codebase's other Nerd Font PUA picks
                // this session (Bluetooth's md-bell_outline mixup) proved
                // that "looks plausible" isn't good enough here.
                text: ""
                anchors {
                    left: parent.left
                    leftMargin: Theme.spacing.launcherRowInset
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.color.textBody
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                renderType: Text.NativeRendering
            }

            TextInput {
                id: passwordInput
                anchors {
                    left: parent.left
                    right: retHint.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: Theme.spacing.launcherRowInset + Theme.spacing.launcherIconLabelGap + 12
                    rightMargin: 8
                }
                enabled: LockService.phase === LockService.phasePrompting
                echoMode: LockService.maskInput ? TextInput.Password : TextInput.Normal
                color: Theme.color.textStrong
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase

                onAccepted: {
                    LockService.submit(text);
                    text = "";
                }
            }

            // "Ret" key hint, matching lock.html's <span class="unit
            // combo"> — a static affordance, not itself interactive.
            Text {
                id: retHint
                text: "Ret"
                anchors {
                    right: parent.right
                    rightMargin: Theme.spacing.launcherRowInset
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.color.textDim
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }
    }

    Component.onCompleted: passwordInput.forceActiveFocus()
}
