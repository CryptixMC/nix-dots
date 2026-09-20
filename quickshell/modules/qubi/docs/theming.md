# Theming the QML frontend

Qubi's QML imports nothing outside `qml/`. Every colour, size and duration
it uses is a token on the `QubiTheme` singleton (`qml/core/QubiTheme.qml`),
which ships complete defaults, so `quickshell -p qml` works with no host.

Embedded in your own shell, hand Qubi your theme object:

```qml
import "modules/qubi/qml"   // wherever the checkout or submodule is mounted

ShellRoot {
    Qubi {
        theme: MyTheme                          // optional
        config: ({ defaultCwd: "/home/me/src" }) // optional, see QubiConfig.qml
        features: ({ voice: false })             // optional
    }
}
```

`theme` may be any object shaped like
`{ color, font, radius, spacing, motion, qubi }`, every part optional. Each
token resolves, most specific first:

1. `theme.qubi.<group>.<token>`, an explicit override for Qubi
2. `theme.<group>.<token>`, your shell's own token of the same name, so
   Qubi picks up your `font.family`, `color.fg`, `radius.panel`, ... for free
3. Qubi's default

Bindings are live: switching your theme re-themes Qubi. Easing curves under
`motion` may be given as strings (`"OutCubic"`).

For a bar widget, `QubiStatusModel` exposes `state`, `title`, `body`, `hint`
and `protocolMismatch` with no visuals of its own.
