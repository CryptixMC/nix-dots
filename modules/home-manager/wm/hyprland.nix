{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
  toLua = lib.generators.toLua { };

  mainMod = "SUPER"; # Sets "Windows" key as main modifier
  terminal = "ghostty";
  fileManager = "nautilus";
  claudeApp = "claude-desktop";
  editor = "zeditor";
  browser = "zen-twilight";

  # Home Manager's Lua backend maps each top-level `settings.<name>` key to
  # one `hl.<name>(...)` call (list values -> one call per element; `_args`
  # -> multi-argument call instead of a single table arg). Real dispatcher
  # calls (hl.dsp.*) can't be expressed as plain Nix data, so they're
  # injected as raw Lua source via lib.generators.mkLuaInline. Function/field
  # names below are taken from Hyprland's own example config
  # (https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua) and
  # verified against src/config/lua/bindings/LuaBindingsDispatchers.cpp.
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
  workspaceBinds = lib.concatMap (
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
  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland >=0.55 configures via Lua instead of the deprecated hyprlang
    # (.conf) syntax. See https://wiki.hypr.land/Configuring/Start/
    configType = "lua";

    settings = {
      # See https://wiki.hypr.land/Configuring/Basics/Monitors/
      monitor = [
        {
          output = "DP-6";
          mode = "1920x1080";
          position = "0x420";
          scale = "1";
        }
        {
          output = "HDMI-A-2";
          mode = "1920x1080";
          position = "1920x0";
          scale = "1";
          transform = 3;
        }
        {
          output = "eDP-1";
          mode = "preferred";
          position = "auto";
          scale = "1";
        }
      ];

      # hl.env(name, value) takes two positional strings, unlike hyprlang's
      # comma-joined `env = NAME,VALUE`. See
      # https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
      env = [
        { _args = [ "XCURSOR_SIZE" "24" ]; }
        { _args = [ "XCURSOR_THEME" "XCursor-Pro-Dark" ]; }

        # Default every Vulkan/OpenGL app (every Steam game, no per-game
        # launch options needed) to the AMD eGPU (1002:73bf @ 0000:54:00.0)
        # when it's present. MESA_VK_DEVICE_SELECT is Mesa's own Vulkan
        # device-selection layer (checked first); DRI_PRIME is the older,
        # more universally-honored fallback for OpenGL and as a secondary
        # Vulkan signal. Expected to fall through to the iGPU gracefully when
        # the eGPU is undocked and this PCI ID doesn't exist — verify this
        # empirically (see README.md) since it wasn't confirmed against docs.
        { _args = [ "MESA_VK_DEVICE_SELECT" "1002:73bf" ]; }
        { _args = [ "DRI_PRIME" "0000:54:00.0" ]; }
      ];

      # general/decoration/animations(.enabled)/misc/render/cursor/input/
      # dwindle/master are NOT top-level hl.<name>(...) calls — they must be
      # nested under one hl.config({...}) call. See
      # https://wiki.hypr.land/Configuring/Basics/Variables/
      config = {
        general = {
          gaps_in = 3;
          gaps_out = 5;
          border_size = 2;
          # Flat dotted keys (not nested `col = {...}`): stylix's own
          # hyprland module sets these the same way, and only a flat key at
          # the identical Nix attribute path actually participates in that
          # option merge — mkForce on a differently-shaped (nested) path
          # would silently lose to stylix's value at Lua-table-iteration
          # time instead of at Nix-module-merge time.
          "col.active_border" = lib.mkForce {
            colors = [
              "rgb(cf01ed)"
              "rgb(4301ed)"
            ];
            angle = 45;
          };
          "col.inactive_border" = lib.mkForce "rgba(595959aa)";
          resize_on_border = false;
          allow_tearing = false;
          layout = "dwindle";
        };

        decoration = {
          rounding = 5;
          rounding_power = 2;
          active_opacity = 1.0;
          inactive_opacity = 0.85;

          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
            color = lib.mkForce "rgba(1a1a1aee)"; # stylix also sets this
          };

          blur = {
            enabled = true;
            size = 3;
            passes = 1;
            vibrancy = 0.1696;
          };
        };

        animations.enabled = true;

        dwindle.preserve_split = true; # You probably want this

        master.new_status = "master";

        misc = {
          force_default_wallpaper = 0; # Set to 0 or 1 to disable the anime mascot wallpapers
          disable_hyprland_logo = lib.mkForce false; # stylix's hyprpaper target sets this to true
        };

        render.direct_scanout = false;

        cursor.no_hardware_cursors = true;

        input = {
          kb_layout = "us";
          kb_variant = "";
          kb_model = "";
          kb_options = "";
          kb_rules = "";

          follow_mouse = 1;

          sensitivity = 0; # -1.0 - 1.0, 0 means no modification.

          touchpad.natural_scroll = false;
        };
      };

      # Bezier curves (hl.curve(name, {...})) and per-leaf animation configs
      # (hl.animation({...})) are separate top-level calls, not nested under
      # animations like hyprlang's `bezier =` / `animation =` keywords. See
      # https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
      curve = [
        {
          _args = [
            "easeOutQuint"
            {
              type = "bezier";
              points = [
                [ 0.23 1 ]
                [ 0.32 1 ]
              ];
            }
          ];
        }
        {
          _args = [
            "easeInOutCubic"
            {
              type = "bezier";
              points = [
                [ 0.65 0.05 ]
                [ 0.36 1 ]
              ];
            }
          ];
        }
        {
          _args = [
            "linear"
            {
              type = "bezier";
              points = [
                [ 0 0 ]
                [ 1 1 ]
              ];
            }
          ];
        }
        {
          _args = [
            "almostLinear"
            {
              type = "bezier";
              points = [
                [ 0.5 0.5 ]
                [ 0.75 1.0 ]
              ];
            }
          ];
        }
        {
          _args = [
            "quick"
            {
              type = "bezier";
              points = [
                [ 0.15 0 ]
                [ 0.1 1 ]
              ];
            }
          ];
        }
      ];

      animation = [
        {
          leaf = "global";
          enabled = true;
          speed = 10;
          bezier = "default";
        }
        {
          leaf = "border";
          enabled = true;
          speed = 5.39;
          bezier = "easeOutQuint";
        }
        {
          leaf = "windows";
          enabled = true;
          speed = 4.79;
          bezier = "easeOutQuint";
        }
        {
          leaf = "windowsIn";
          enabled = true;
          speed = 4.1;
          bezier = "easeOutQuint";
          style = "popin 87%";
        }
        {
          leaf = "windowsOut";
          enabled = true;
          speed = 1.49;
          bezier = "linear";
          style = "popin 87%";
        }
        {
          leaf = "fadeIn";
          enabled = true;
          speed = 1.73;
          bezier = "almostLinear";
        }
        {
          leaf = "fadeOut";
          enabled = true;
          speed = 1.46;
          bezier = "almostLinear";
        }
        {
          leaf = "fade";
          enabled = true;
          speed = 3.03;
          bezier = "quick";
        }
        {
          leaf = "layers";
          enabled = true;
          speed = 3.81;
          bezier = "easeOutQuint";
        }
        {
          leaf = "layersIn";
          enabled = true;
          speed = 4;
          bezier = "easeOutQuint";
          style = "fade";
        }
        {
          leaf = "layersOut";
          enabled = true;
          speed = 1.5;
          bezier = "linear";
          style = "fade";
        }
        {
          leaf = "fadeLayersIn";
          enabled = true;
          speed = 1.79;
          bezier = "almostLinear";
        }
        {
          leaf = "fadeLayersOut";
          enabled = true;
          speed = 1.39;
          bezier = "almostLinear";
        }
        {
          leaf = "workspaces";
          enabled = true;
          speed = 1.94;
          bezier = "almostLinear";
          style = "fade";
        }
        {
          leaf = "workspacesIn";
          enabled = true;
          speed = 1.21;
          bezier = "almostLinear";
          style = "fade";
        }
        {
          leaf = "workspacesOut";
          enabled = true;
          speed = 1.94;
          bezier = "almostLinear";
          style = "fade";
        }
      ];

      # Example per-device config, see
      # https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
      device = {
        name = "epic-mouse-v1";
        sensitivity = -0.5;
      };

      # See https://wiki.hypr.land/Configuring/Basics/Binds/ for more.
      # bindm/bindel/bindl don't exist as separate Lua functions — the mouse/
      # locked/repeating flags they used to carry are now opts on hl.bind
      # itself (mouse=true, locked=true, repeating=true below).
      bind =
        [
          (mkExecBind "${mainMod} + Q" terminal)
          (mkBind "${mainMod} + C" (dsp "hl.dsp.window.close()") null)
          (mkBind "${mainMod} + M" (dsp "hl.dsp.exit()") null)
          (mkExecBind "${mainMod} + E" fileManager)
          (mkBind "${mainMod} + V" (dsp "hl.dsp.window.float()") null)
          # Quickshell launcher (quickshell/modules/launcher/, see TODO.md
          # §3) now owns Walker's old SUPER+R slot — Walker is hidden (see
          # walker.nix's import in hosts/carbon/home.nix and the `walker`/
          # `elephant` package removals) rather than deleted, so this can be
          # pointed back at `walker -t float` easily if ever needed. Runs
          # inside the already-running Quickshell instance (not a separate
          # process), so it's shown/hidden via Quickshell's own IPC rather
          # than exec/pkill: `quickshell ipc -p <path> call <target> <fn>`
          # is the verified flag order — `ipc call -p <path> ...` errors
          # out. Walker's rail/grid modes (old SHIFT+R/CTRL+R) have no
          # Quickshell equivalent and were dropped along with Walker itself.
          (mkExecBind "${mainMod} + R" "quickshell ipc -p ~/nix-dots/quickshell call launcher toggle")
          # Theme registry (quickshell/theme/, see the theme-registry
          # migration): cycles the active theme live via IPC, no restart.
          (mkExecBind "${mainMod} + T" "quickshell ipc -p ~/nix-dots/quickshell call theme next")
          (mkBind "${mainMod} + P" (dsp "hl.dsp.window.pseudo()") null) # dwindle
          (mkBind "${mainMod} + J" (dsp "hl.dsp.layout(${toLua "togglesplit"})") null)
          (mkExecBind "${mainMod} + Z" editor)
          (mkExecBind "${mainMod} + F" browser)
          (mkExecBind "${mainMod} + A" claudeApp)
          (mkBind "${mainMod} + L" (dsp "hl.dsp.window.fullscreen()") null)

          # Move focus with mainMod + arrow keys
          (mkBind "${mainMod} + left" (dsp "hl.dsp.focus({ direction = \"left\" })") null)
          (mkBind "${mainMod} + right" (dsp "hl.dsp.focus({ direction = \"right\" })") null)
          (mkBind "${mainMod} + up" (dsp "hl.dsp.focus({ direction = \"up\" })") null)
          (mkBind "${mainMod} + down" (dsp "hl.dsp.focus({ direction = \"down\" })") null)
        ]
        # Switch workspaces with mainMod + [0-9]; move active window to a
        # workspace with mainMod + SHIFT + [0-9]
        ++ workspaceBinds
        ++ [
          # Example special workspace (scratchpad)
          (mkBind "${mainMod} + S" (dsp "hl.dsp.workspace.toggle_special(${toLua "magic"})") null)
          (mkBind "${mainMod} + SHIFT + S" (dsp "hl.dsp.window.move({ workspace = ${toLua "special:magic"} })") null)

          # Scroll through existing workspaces with mainMod + scroll
          (mkBind "${mainMod} + mouse_down" (dsp "hl.dsp.focus({ workspace = ${toLua "e+1"} })") null)
          (mkBind "${mainMod} + mouse_up" (dsp "hl.dsp.focus({ workspace = ${toLua "e-1"} })") null)

          # Move/resize windows with mainMod + LMB/RMB and dragging
          (mkBind "${mainMod} + mouse:272" (dsp "hl.dsp.window.drag()") { mouse = true; })
          (mkBind "${mainMod} + mouse:273" (dsp "hl.dsp.window.resize()") { mouse = true; })

          # Laptop multimedia keys for volume and LCD brightness
          (mkBind "XF86AudioRaiseVolume" (exec "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+") {
            locked = true;
            repeating = true;
          })
          (mkBind "XF86AudioLowerVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") {
            locked = true;
            repeating = true;
          })
          (mkBind "XF86AudioMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") {
            locked = true;
            repeating = true;
          })
          (mkBind "XF86AudioMicMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") {
            locked = true;
            repeating = true;
          })
          (mkBind "XF86MonBrightnessUp" (exec "brightnessctl -e4 -n2 set 5%+") {
            locked = true;
            repeating = true;
          })
          (mkBind "XF86MonBrightnessDown" (exec "brightnessctl -e4 -n2 set 5%-") {
            locked = true;
            repeating = true;
          })
          (mkBind "${mainMod} + F8" (exec "brightnessctl -d platform::kbd_backlight set 1-") {
            locked = true;
            repeating = true;
          })
          (mkBind "${mainMod} + F9" (exec "brightnessctl -d platform::kbd_backlight set +1") {
            locked = true;
            repeating = true;
          })

          # Requires playerctl
          (mkBind "XF86AudioNext" (exec "playerctl next") { locked = true; })
          (mkBind "XF86AudioPause" (exec "playerctl play-pause") { locked = true; })
          (mkBind "XF86AudioPlay" (exec "playerctl play-pause") { locked = true; })
          (mkBind "XF86AudioPrev" (exec "playerctl previous") { locked = true; })

          # Gracefully eject the Thunderbolt eGPU before physically unplugging
          # it — waits for a "safe to unplug" notification. See egpu-eject
          # .service in modules/nixos/hardware/amd.nix for the teardown sequence.
          (mkExecBind "${mainMod} + SHIFT + U" "sudo systemctl start egpu-eject.service")

          # Launch the whole Steam client + every game inside one gamescope
          # instance (Valve's own Deck-style session mode, already enabled via
          # programs.steam.gamescopeSession in games.nix) nested inside this
          # Hyprland session — no per-game launch options needed, and no need
          # to fight the GDM autologin/defaultSession to reach the session
          # picker. Device selection comes from the MESA_VK_DEVICE_SELECT/
          # DRI_PRIME env vars above.
          (mkExecBind "${mainMod} + G" "gamescope --steam -W 1920 -H 1080 -f -- steam")
        ];
    };

    # Autostart lives here rather than in `settings`: exec-once/exec are not
    # plain keywords in Lua-Hyprland, they're the hl.on("hyprland.start", ...)
    # event API (settings.exec-once generates invalid Lua under configType =
    # "lua" — see nix-community/home-manager#9468). This is raw Lua text
    # passed through as-is, so hl.on/hl.exec_cmd are real calls here already.
    extraConfig = ''
      hl.on("hyprland.start", function()
          -- Quickshell (quickshell/, see TODO.md §3) is the default bar AND
          -- launcher now (SUPER+R). Waybar/Walker are hidden, not removed —
          -- disabled in waybar.nix / commented out of the walker.nix import
          -- and the walker+elephant package lists — so there's no `waybar`
          -- or `elephant` process to autostart here anymore.
          --
          -- hyprpaper dropped: quickshell/modules/wallpaper/Wallpaper.qml
          -- now renders the Background layer for every theme (including
          -- static-only ones), sourced from themes/<name>/theme.json's
          -- wallpaper block — running hyprpaper alongside it would race two
          -- Background-layer clients for the same output. hyprpaper package
          -- stays installed (modules/nixos/wm/hyprland.nix) as a manual
          -- fallback if ever needed.
          hl.exec_cmd("quickshell -p ~/nix-dots/quickshell")
          hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
      end)
    '';

    # See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
    # Please note permission changes here require a Hyprland restart and are
    # not applied on-the-fly for security reasons.
    # settings.permission = [
    #   { _args = [ "/usr/(bin|local/bin)/grim" "screencopy" "allow" ]; }
    #   { _args = [ "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland" "screencopy" "allow" ]; }
    #   { _args = [ "/usr/(bin|local/bin)/hyprpm" "plugin" "allow" ]; }
    # ];
  };
}
