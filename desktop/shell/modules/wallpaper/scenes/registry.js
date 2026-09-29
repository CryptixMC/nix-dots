.pragma library

// Pickable live-wallpaper scenes, shared by Theme.qml and every theme's picker.
// Adding a scene also requires a Component in WallpaperContent.qml's
// sceneComponents; Components can't be built from a string at runtime.
var scenes = [
    { name: "Orbital", label: "Orbital" },
    { name: "NeuralNet", label: "Neural Net" },
];
var names = scenes.map(s => s.name);
