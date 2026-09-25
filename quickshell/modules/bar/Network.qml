import QtQuick
import Quickshell
import Quickshell.Networking

// Network module. Click opens a network switcher flyout (NetworkPopup.qml)
// instead of launching `nmtui` directly — same upgrade Volume.qml already
// got over pavucontrol, nmtui is still one click away via the flyout's "›"
// link. A bandwidth (↑/↓) tooltip line is dropped — Quickshell.Networking
// exposes no rate property, and custom /sys/class/net byte-counter diffing
// wasn't judged worth it for this pass.
BarIcon {
    id: root

    // `type` (DeviceType.Wifi/Wired), not duck-typing via `networks`
    // presence -- confirmed live this session that `networks` is defined
    // (non-undefined) on EVERY NetworkDevice regardless of type in this
    // Quickshell version, so the old `d.networks !== undefined` check
    // matched every device including plain ethernet, and `d.networks ===
    // undefined` for wiredDevices matched NONE. In practice that meant
    // `wifiDevices[0]` could silently be the ethernet device (whichever
    // happened to sort first) -- NetworkPopup then read a real, connected,
    // but entirely wifi-less device's `.networks`, which is why the
    // network list rendered permanently empty even with wifi connected and
    // real networks visible in `nmcli device wifi list`. `wiredDevices`
    // was simultaneously always empty, so the wired-connection branches of
    // the glyph/tooltip logic below could never fire either.
    readonly property var wifiDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    readonly property var wiredDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wired)

    readonly property var connectedWifi: wifiDevices.find(d => d.connected) ?? null
    readonly property var connectedWired: wiredDevices.find(d => d.connected) ?? null
    readonly property var linkedWired: wiredDevices.find(d => d.hasLink && !d.connected) ?? null
    readonly property var activeWifiNetwork: connectedWifi ? connectedWifi.networks.values.find(n => n.connected) ?? null : null

    glyph: {
        if (connectedWifi)
            return "󰤨";
        if (connectedWired)
            return "󰈀";
        if (linkedWired)
            return "󰤫";
        return "󰤭";
    }

    // No wifi device at all (ethernet-only machine) falls back to the old
    // direct-nmtui behavior — nothing for the switcher popup to list.
    onClickFn: () => {
        if (root.wifiDevices.length > 0)
            popup.visible = !popup.visible;
        else
            Quickshell.execDetached(["ghostty", "-e", "nmtui"]);
    }

    tooltipTitle: "NETWORK"
    tooltipBody: {
        if (connectedWifi)
            return activeWifiNetwork?.name ?? "connected";
        if (connectedWired)
            return connectedWired.name ?? "ethernet";
        if (linkedWired)
            return "cable connected, no IP";
        return "disconnected";
    }
    tooltipMuted: (connectedWifi ?? connectedWired)?.address ?? ""

    NetworkPopup {
        id: popup
        anchorItem: root
        wifiDevice: root.wifiDevices[0] ?? null
    }
}
