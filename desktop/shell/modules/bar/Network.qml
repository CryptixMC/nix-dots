import QtQuick
import Quickshell
import Quickshell.Networking
import "popups"

// Network module. Click opens a switcher flyout (NetworkPopup.qml).
// Quickshell.Networking exposes no bandwidth rate; see NetSpeed.qml.
BarIcon {
    id: root

    // Filter on `type`, not `networks` presence: `networks` is defined on
    // every NetworkDevice in this Quickshell version, including ethernet.
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

    // No wifi device (ethernet-only): nothing to list, open nmtui directly.
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
