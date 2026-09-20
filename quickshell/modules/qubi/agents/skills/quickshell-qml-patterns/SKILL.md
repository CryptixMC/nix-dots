---
name: quickshell-qml-patterns
description: Structural conventions for this repo's Quickshell/QML modules, and specific runtime bugs that have crashed the live shell before. Load before writing or editing any .qml file here.
---

# Quickshell/QML patterns and traps in this repo

## The live shell is real and fragile — never skip staging
Liam's running Quickshell instance hot-reloads `quickshell/` on file
change. A single bad QML file can take down the **entire** shell (bar,
wallpaper, launcher, everything), not just the module you're editing —
this has actually happened (an `IpcHandler` used without importing
`Quickshell.Io`). Protocol for any new module:
1. Write it in an isolated staging directory outside the repo (mirror the
   real `quickshell/modules/<name>/` path depth so relative imports like
   `../../theme` resolve identically — symlink the real `theme/` dir in).
2. Launch a **second** Quickshell instance against a staging-only
   `shell.qml` that imports *only* the module under test.
3. Confirm it loads clean (`INFO: Configuration Loaded`, no `WARN`/error
   about your module) and exercise its IPC target a few times.
4. Only then copy the files into the real repo and uncomment/add its
   `shell.qml` registration — that registration step is always last.
5. After registering, check the *live* instance's own log
   (`readlink -f /run/user/$UID/quickshell/by-pid/<livepid>` →
   `log.log`) for "Reloading configuration... Configuration Loaded" with
   no new warnings, and confirm the process is still running.

## Structural conventions (copy these, don't reinvent)
- **State singleton**: `pragma Singleton`, plain `QtObject`, a `visible`
  bool, a `toggle()`/`hide()` pair, and any feature-specific state as
  plain properties. Data that should be extensible later (action lists,
  tabs) lives as a `readonly property var` list of `{id, label, ...}`
  objects, iterated with a `Repeater` — one more list entry adds a
  feature, not a new code path.
- **Overlay component**: `PanelWindow`, `anchors { top: true; bottom:
  true; left: true; right: true }`, `exclusiveZone: 0`,
  `WlrLayershell.layer: WlrLayer.Overlay`, `color: "transparent"`, a
  full-window `MouseArea` that closes on click-outside, a centered
  `Rectangle` box with `Theme.color.launcherBg`/`launcherBorder`, and an
  `IpcHandler { target: "..." function foo(): void { ... } }` for the
  Hyprland-keybind-triggered toggle (`quickshell ipc -p
  ~/nix-dots/quickshell call <target> <function>`).
- **qmldir**: `singleton FooState 1.0 FooState.qml` then `Foo 1.0
  Foo.qml` — always declare the singleton line first.
- Every file using `Process`/`SplitParser`/`StdioCollector`/`IpcHandler`
  MUST `import Quickshell.Io` explicitly — a missing import here doesn't
  just break that file, it crashes the whole shell's config load.

## Specific runtime bugs already found in this codebase
- **Boolean anchors crash** (the incident `qml-lint-repo` exists to
  catch): assigning a plain `anchors { ... }`-style block to something
  that isn't a real Anchors-typed property produces "Invalid property
  assignment: unsupported type QQuickAnchorLine" at runtime — a QML-only
  error `nix flake check` cannot see.
- **`Loader`/`implicitHeight` binding loops**: giving a `Loader` an
  explicit `height: item.height` fights Qt's own default (a sized Loader
  force-resizes its content) and can freeze at 0. Fixing it by making
  `implicitHeight` depend on `height` (even indirectly) creates a genuine
  binding loop, since `Item.height`'s own default binding *is*
  `implicitHeight`. Compute height into an independent `readonly property
  real computedHeight` and bind both `height` and `implicitHeight` to
  that, never to each other.
- **Inactive `Loader`s still report old height** to layout containers
  unless given `visible: active` — a `Column` excludes invisible children
  from its layout sum regardless of their still-live implicit size,
  which is what actually fixes height-accumulation-across-tab-switches
  bugs, not toggling `active` alone.
- **`Process` has no "close stdin" primitive** — the installed
  `quickshell-io.qmltypes` shows only `write(data)` and `signal(sig)` on
  `Process`, no explicit EOF/close method. Writing to stdin and then
  immediately setting `running: false` sends a kill signal, which can
  race a subprocess's own read-until-EOF logic and lose data. Prefer a
  tool's own "take content as a positional argument" mode when one exists
  (e.g. `wl-copy TEXT...` instead of piping to its stdin).
- **`TextInput` vs a two-way singleton binding**: don't bind a
  `TextInput.text` property both ways to a singleton property — the
  `TextInput` sets `text` imperatively on every keystroke, which
  permanently breaks a declarative `text: SomeState.value` binding on
  the same property the first time the user types. Keep search/input
  text as local `TextInput` state, only pushing the final value out on
  submit.
- **Stray layer-shell surfaces silently eat keyboard input** — before
  concluding a focus/typing bug is in your own component, check
  `hyprctl layers` for an unrelated overlay (e.g. a leftover `slurp`
  process) sitting above yours in the same layer.

## Direct HTTP calls to local services
For a single-shot request that doesn't need `goose acp`'s session
machinery (e.g. calling Ollama's REST API directly), use `Process` with
`curl` and a `SplitParser` for NDJSON streaming responses — see
`ModelBrowser.qml`'s `/api/pull` handling or `ClipboardTransform.qml`'s
`/api/generate` handling for the exact pattern (parse each line inside a
`try`, skip silently on a JSON parse failure since not every line in a
stream is guaranteed valid on its own).
