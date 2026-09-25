.pragma library

// The single list of pickable live-wallpaper scenes, independent of any
// theme -- read by Theme.qml (to validate/resolve a picked override) and
// by the launcher's wallpaper picker (to render one card per entry,
// alongside the theme's own file-based wallpapers). Adding a scene here
// makes it pickable from EVERY theme's picker, not just one.
//
// Wallpaper.qml's `sceneComponents` mapping (name -> Component) stays a
// separate, hand-written object -- Components must be declared
// statically in QML, they can't be built from a string at runtime
// without reopening the Loader.source/required-property problem already
// solved there (see the comment above its orbitalComponent). Adding a
// scene means updating both this list and that mapping; they're
// deliberately kept small and adjacent in intent, not merged, since one
// holds display metadata and the other holds real QML Components.
var scenes = [
    { name: "Orbital", label: "Orbital" },
    { name: "NeuralNet", label: "Neural Net" },
];
var names = scenes.map(s => s.name);
