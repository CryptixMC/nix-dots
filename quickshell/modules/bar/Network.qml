import QtQuick
import Quickshell
import Quickshell.Networking

// Mirrors waybar's "network" module (icons 1:1 from waybar.nix). Click now
// opens a network switcher flyout (NetworkPopup.qml) instead of launching
// `nmtui` directly — same upgrade Volume.qml already got over pavucontrol,
// nmtui is still one click away via the flyout's "›" link. Bandwidth
// (waybar's ↑/↓ tooltip line) is dropped — Quickshell.Networking exposes
// no rate property, and custom /sys/class/net byte-counter diffing wasn't
// judged worth it for this pass.
BarIcon {
    id: root

    // No confirmed type-discrimination API for WifiDevice vs WiredDevice
    // (e.g. `instanceof`) — duck-typed via presence of `networks`, which
    // only a WifiDevice exposes.
    readonly property var wifiDevices: Networking.devices.values.filter(d => d.networks !== undefined)
    readonly property var wiredDevices: Networking.devices.values.filter(d => d.networks === undefined)

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
