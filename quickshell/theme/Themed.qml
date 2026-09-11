import QtQuick

// Generic per-theme component override point. A theme folder can optionally
// ship themes/<name>/components/<Name>.qml — if present, ThemeEntryLoader
// discovers it (see componentOverrides in ThemeDefaults.build()) and this
// Loader picks it up instead of the built-in default, live, on the next
// theme switch (Loader.source is a plain property binding, so it re-resolves
// automatically when Theme.componentOverrides changes). No override present
// falls back to defaultSource — the same file this Themed{} call replaces.
Loader {
    id: root

    required property string componentName
    required property url defaultSource

    source: Theme.componentOverrides[componentName] ?? defaultSource
    asynchronous: false
}
