import QtQuick

// Per-theme component override: loads themes/<name>/components/<Name>.qml if
// the active theme ships one, else defaultSource. Re-resolves on theme switch.
Loader {
    id: root

    required property string componentName
    required property url defaultSource

    source: Theme.componentOverrides[componentName] ?? defaultSource
    asynchronous: false
}
