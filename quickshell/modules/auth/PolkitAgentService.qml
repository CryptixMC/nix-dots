pragma Singleton
import QtQuick
import Quickshell.Services.Polkit

// Quickshell registers itself as the session's polkit authentication agent,
// replacing polkit-gnome-authentication-agent-1 (started today from
// modules/home-manager/wm/hyprland.nix's autostart). Only one agent can hold
// the slot per session -- confirmed live in staging: attempting to register
// a second one while polkit-gnome already holds it fails with
// "An authentication agent already exists for the given subject".
//
// Relays `authenticationRequestStarted` outward rather than leaving
// consumers to bind on `flow !== null` directly -- confirmed live (real
// pkexec-triggered flow, not a mock) that binding a window's `visible`
// straight to the singleton's `flow` property never actually became
// visible, even though the flow genuinely reached this agent (the job's
// own output showed a live PAM conversation happening). The proven-working
// pattern (lifted from Omarchy's own PolkitAgent.qml, which ships this
// exact integration in production) is: bind visibility to `isActive`
// instead, and treat `authenticationRequestStarted` as the "a new flow
// began" trigger.
//
// `path` includes a per-construction-time suffix rather than a fixed
// string -- confirmed live: registering at a FIXED path fails silently
// (isRegistered stays false, no warning logged) on every QML hot-reload
// after the first successful registration, even though the prior
// PolkitAgent object (and its D-Bus registration) should be long torn
// down by the time the new one tries. Only a full process restart (not a
// reload) recovered it at the fixed path. Root cause unconfirmed -- most
// likely the daemon-side listener registration for the old object path
// isn't cleaned up synchronously with QML object destruction, so the new
// registration at the SAME path collides with a stale one polkitd hasn't
// noticed is dead yet. A unique path per instance sidesteps the collision
// entirely rather than chasing the teardown race. This matters well beyond
// Phase 0's one-time swap: hot-reloading is this repo's entire normal dev
// workflow (SKILL.md's staging protocol included), so a fixed path would
// have left the agent broken after nearly every live edit to ANY file in
// the tree, not just this one.
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
