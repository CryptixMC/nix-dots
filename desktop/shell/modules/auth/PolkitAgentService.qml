pragma Singleton
import QtQuick
import Quickshell.Services.Polkit

// Registers Quickshell as the session's polkit agent (only one agent may hold
// the slot per session). Consumers should bind visibility to `isActive` and
// use `authenticationRequestStarted`; binding to `flow` directly never fires.
// `path` is unique per instance because re-registering a fixed path fails
// silently after a hot reload.
Item {
    id: root

    PolkitAgent {
        id: agentImpl
        path: `/org/quickshell/PolkitAgent-${Date.now()}`

        onAuthenticationRequestStarted: root.authenticationRequestStarted()
    }

    readonly property alias isRegistered: agentImpl.isRegistered
    readonly property alias isActive: agentImpl.isActive
    readonly property alias flow: agentImpl.flow

    signal authenticationRequestStarted
}
