# Home Manager's Lua backend maps each top-level `settings.<name>` key to one
# `hl.<name>(...)` call (list values -> one call per element; `_args` -> a
# multi-argument call instead of a single table arg). Real dispatcher calls
# (hl.dsp.*) can't be expressed as plain Nix data, so they're injected as raw
# Lua source via lib.generators.mkLuaInline. Function/field names are taken
# from Hyprland's own example config
# (https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua) and
# verified against src/config/lua/bindings/LuaBindingsDispatchers.cpp.
#
# See the hyprland-lua-configtype-pitfall memory for why sections (general,
# decoration, animations, ...) must NOT go through this path -- they need
# `settings.config.*`, not a top-level hl.<name>(...) call.
{ lib }:
let
  inherit (lib.generators) mkLuaInline;
  toLua = lib.generators.toLua { };

  dsp = luaExpr: mkLuaInline luaExpr;
  exec = cmd: dsp "hl.dsp.exec_cmd(${toLua cmd})";

  # settings.bind entries render as hl.bind(<keys>, <dispatcher>, <opts>).
  mkBind =
    keys: dispatcher: opts:
    {
      _args = [
        keys
        dispatcher
      ]
      ++ lib.optional (opts != null) opts;
    };
  mkExecBind = keys: cmd: mkBind keys (exec cmd) null;

  # mainMod + [0-9] workspace switch/move binds. Key "0" maps to workspace
  # 10, same as the old hyprlang `$mainMod, 0, workspace, 10`.
  workspaceBinds =
    mainMod:
    lib.concatMap (
      n:
      let
        key = if n == 10 then "0" else toString n;
      in
      [
        (mkBind "${mainMod} + ${key}" (dsp "hl.dsp.focus({ workspace = ${toString n} })") null)
        (mkBind "${mainMod} + SHIFT + ${key}" (dsp "hl.dsp.window.move({ workspace = ${toString n} })") null)
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
