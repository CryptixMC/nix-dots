pragma Singleton
import QtQuick

// Hardcoded, not a `getent passwd` shell-out: this is a single-user laptop
// (one real account, "cryptix"), so runtime user enumeration is unneeded
// complexity on a trusted pre-login surface. Manual edit needed if a
// second account is ever added — accepted tradeoff for v1, see the
// greeter plan's scope boundary.
QtObject {
    readonly property string username: "cryptix"
}
