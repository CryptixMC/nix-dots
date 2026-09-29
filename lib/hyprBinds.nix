# Helpers for Home Manager's Lua Hyprland backend: each top-level `settings.<name>`
# becomes an `hl.<name>(...)` call (`_args` -> multi-argument call). Dispatchers
# (hl.dsp.*) aren't plain data, so they're injected via mkLuaInline.
# Config sections (general, decoration, ...) belong in `settings.config.*`, not here.
{ lib }:
let
  inherit (lib.generators) mkLuaInline;
  toLua = lib.generators.toLua { };

  dsp = luaExpr: mkLuaInline luaExpr;
  exec = cmd: dsp "hl.dsp.exec_cmd(${toLua cmd})";

  # settings.bind entries render as hl.bind(<keys>, <dispatcher>, <opts>).
  mkBind = keys: dispatcher: opts: {
    _args = [
      keys
      dispatcher
    ]
    ++ lib.optional (opts != null) opts;
  };
  mkExecBind = keys: cmd: mkBind keys (exec cmd) null;

  # mainMod + [0-9] workspace switch/move binds; key "0" is workspace 10.
  workspaceBinds =
    mainMod:
    lib.concatMap (
      n:
      let
        key = if n == 10 then "0" else toString n;
      in
      [
        (mkBind "${mainMod} + ${key}" (dsp "hl.dsp.focus({ workspace = ${toString n} })") null)
        (mkBind "${mainMod} + SHIFT + ${key}" (dsp "hl.dsp.window.move({ workspace = ${toString n} })")
          null
        )
      ]
    ) (lib.range 1 10);
in
{
  inherit
    dsp
    toLua
    exec
    mkBind
    mkExecBind
    workspaceBinds
    ;
}
