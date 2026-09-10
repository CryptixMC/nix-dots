import QtQuick
import Quickshell.Networking

// Mirrors waybar's "network" module (icons/on-click 1:1 from waybar.nix).
// Bandwidth (waybar's ↑/↓ tooltip line) is dropped — Quickshell.Networking
// exposes no rate property, and custom /sys/class/net byte-counter diffing
// wasn't judged worth it for this pass.
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

    clickCommand: "ghostty -e nmtui"

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
}
