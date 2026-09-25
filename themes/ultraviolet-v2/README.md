# ultraviolet-v2

The Ultraviolet design system's **Violet** role mapping, ported from
`~/Projects/nixos-designer/ultraviolet-v2/` (see that folder's README and
`tokens/tokens.css` — this theme is a transcription of its role table).

`base16.yaml` is byte-identical to `themes/ultraviolet/`'s **on purpose**. v2 is a
semantic remap, not a palette change: the same sixteen values, mapped to different
roles. Everything that distinguishes v2 from v1 lives in `theme.json`.

The short version of the look: hairline violet frames on an opaque ground instead of
translucent cards; violet carries the whole interface (linework, labels, bands); body
text stays grey so dense rows read for hours; and **white is rare** — reserved for the
one thing that is live, the focus ring, and headings and values.

## Why theme.json is mostly a list of recolors

`theme.json`'s `color` block can override **any** key `ThemeDefaults.buildColor()`
produces — both the design-system roles (`line`, `invertBg`, `live`…) and the older
token names the QML already reads (`launcherBg`, `clockFg`…). Overriding the latter is
what lets most of this restyle happen with no QML change at all: a surface keeps
reading the token it always read, and the token now resolves to a violet hairline.

Roles are for what v1 had no token for — a row hover band, a "this is live" white, a
soft divider. Those are the parts that did need QML work.

## Entries that aren't self-explanatory

**`criticalBlink.dimTo: 1`** — this is the "no critical blink" ruling expressed as
data. The design system says critical is colour on the thing carrying the problem and
*nothing else changes*, so the 1 s opacity pulse goes. `CriticalBlink.qml` animates
`opacity` from `dimTo` to `restoreTo`; setting both to `1` makes it a no-op without
touching the QML or the component's other consumers. To get the blink back, restore
`"dimTo": 0.2`.

**`accentPink` stays `base08`** even though the focused workspace used to be pink.
`base08` is genuinely the critical colour elsewhere (battery, temperature), so
recoloring it would break those. The workspace indicator moved to `invertBg` in
`Workspaces.qml` instead — a structural change, not a recolor.

**`sliderTrack: 1`, not the 3px the other radii use.** `tokens.css` puts marks and
bars 6px and under on `--uv-radius-xs` (1px); the volume track is one of those. The
other three radii are the 3px bevel.

**`easing: "InOutQuad"`** stands in for the system's single curve,
`cubic-bezier(0.2,0,0,1)`. There is no stock Qt equivalent and `Easing.Bezier` needs a
`bezierCurve` alongside `easing.type` that this repo's consumers don't bind — see the
comment above `easingMap` in `quickshell/theme/ThemeDefaults.qml`. Same shape,
indistinguishable across the 120–320 ms range v2 caps motion at.

**`qubi` carries only `motion`.** Qubi resolves each token
`host.qubi.<group>.<token>` → `host.<group>.<token>` → its own default, and every
colour and radius it names is already a key in `host.color` / `host.radius`. So it
inherits the whole Violet mapping for free, and the only thing left to state is its
chat slide, brought under v2's 320 ms cap.

## Wallpaper

A fourth `wallpaper.engine`, `"scene"`, renders a live QML component
(`quickshell/modules/wallpaper/scenes/Orbital.qml`) instead of an image or GIF —
the orbital plate from the design folder's `wallpaper/wallpaper.html`
(itself first prototyped as an animated mockup, `Animated.dc.html`), drawn
entirely in the violet ramp except the satellite and the arc it has
already flown, which are white. That is the same rule the GUI follows:
when everything is violet, the one non-violet thing is what changed.

Every number the mockup invented is now real:

- **CPU** sets the satellite's orbital speed — idle drifts a ~60s lap,
  a pegged core pulls that down to ~8s. Above 85% CPU sustained for 5s
  the scene also sheds its own tick rate (24Hz → 8Hz satellite, 3Hz →
  1Hz globe) so the wallpaper doesn't add load back onto the thing it's
  reporting; it restores after 5s back under 70%.
- **Free RAM** sets orbit radius — the satellite decays toward the
  planet as memory fills, smoothed over 2s so it reads as a drift, not
  a snap. It's clamped well outside the limb so it can never appear to
  touch the planet.
- **Network throughput** drifts the background dot grid; going offline
  flips the state chip to `[ OCCULTED ]` and dims (not hides) the
  satellite, so "no network" reads differently from "behind the
  planet."
- The four readout rows are CPU / TEMP / NET / LOAD in real numbers;
  the hero number is memory in use (MiB); the subpoint lat/lon, orbit
  count, and follow-tag are genuine outputs of the same orbit math, not
  redressed decoration.

See `quickshell/services/SystemStats.qml` for where each number comes
from, and `quickshell/modules/wallpaper/scenes/orbital.js` for the
projection math (a direct port of the mockup's, with sample counts cut
2.5–3.7x and terminator edges bisected back to sub-pixel — see the
comments there for the reasoning).

**Theming.** Two of the design's four accent hexes (`#c050ff`, `#d35cf7`)
aren't design-system roles, just the 2nd/3rd rungs of a pure-desaturation
ramp off `lineStrong` (`#b047ff`, h277 s0.72 v1.00 → s0.69 → s0.63,
constant hue/value). `Orbital.qml`'s `rampStep()` derives them from
`Theme.color.lineStrong` at those measured saturation ratios instead of
hardcoding the hexes, so the scene stays coherent (a monochrome ramp) if
ever opted into a non-monochrome palette like catppuccin — it just won't
look *designed* for one. It only runs at all where a theme's `theme.json`
says `"engine": "scene"`; nothing else changes for other themes.

**Revert:** `"engine": "scene"` → `"engine": "gif"` in this theme's
`theme.json`. One word — `orbital-2560x1600.gif` stays on disk and
`"scene": "Orbital"` stays in the JSON (inert whenever `engine` isn't
`"scene"`), so the same one-word edit un-reverts it too.

`alyssa.png` stays as the `image` fallback (used when a wallpaper override
is picked from the launcher's Themes tab, which forces `engine` back to
`static`/`gif` and so switches the scene off) and remains pickable there.
