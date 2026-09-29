{
  config,
  lib,
  pkgs,
  ...
}:
let
  # hl.dsp.*/mkLuaInline mechanics are explained in lib/hyprBinds.nix.
  hyprBinds = import ../../../lib/hyprBinds.nix { inherit lib; };
  inherit (hyprBinds)
    dsp
    toLua
    exec
    mkBind
    mkExecBind
    ;

  mainMod = "SUPER";
  terminal = "ghostty";
  fileManager = "nautilus";
  claudeApp = "claude-desktop";
  editor = "zeditor";
  browser = "zen-twilight";

  workspaceBinds = hyprBinds.workspaceBinds mainMod;
in
{
  # satty's -o doesn't create missing parent directories.
  home.file."Pictures/Screenshots/.keep".text = "";

  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland >=0.55 config format; hyprlang (.conf) is deprecated.
    configType = "lua";

    settings = {
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

      # hl.env takes two positional strings, unlike hyprlang's `env = NAME,VALUE`.
      env = [
        {
          _args = [
            "XCURSOR_SIZE"
            "24"
          ];
        }
        {
          _args = [
            "XCURSOR_THEME"
            "XCursor-Pro-Dark"
          ];
        }

        # Prefer the eGPU for Vulkan/OpenGL when docked; expected to fall back to
        # the iGPU when undocked (unverified).
        {
          _args = [
            "MESA_VK_DEVICE_SELECT"
            "1002:73bf"
          ];
        }
        {
          _args = [
            "DRI_PRIME"
            "0000:54:00.0"
          ];
        }
      ];

      # general/decoration/animations/misc/render/cursor/input/dwindle/master
      # must nest under one hl.config({...}) call, not separate top-level calls.
      config = {
        general = {
          gaps_in = 2;
          gaps_out = 4;
          border_size = 1;
          # Flat dotted key so mkForce hits stylix's exact attribute path. Kept as a
          # same-colour gradient to match the shape Theme.qml writes live via hyprctl.
          "col.active_border" = lib.mkForce {
            colors = [
              "rgb(b047ff)"
              "rgb(b047ff)"
            ];
            angle = 45;
          };
          "col.inactive_border" = lib.mkForce "rgba(8850ff5c)";
          resize_on_border = false;
          allow_tearing = false;
          layout = "dwindle";
        };

        # Flat theme: no shadow, blur or opacity. Rounding matches the shell's
        # radius.panel in desktop/themes/ultraviolet-v2/theme.json.
        decoration = {
          rounding = 3;
          rounding_power = 2;
          active_opacity = 1.0;
          inactive_opacity = 1.0;

          shadow = {
            enabled = false;
            range = 0;
            render_power = 3;
            color = lib.mkForce "rgba(1a1a1aee)"; # stylix also sets this
          };

          blur = {
            enabled = false;
            size = 3;
            passes = 1;
            vibrancy = 0.1696;
          };
        };

        # Group colours are separate from general.col.* and stylix sets them too;
        # flat dotted keys for the same mkForce reason as above.
        group = {
          "col.border_active" = lib.mkForce "rgb(b047ff)";
          "col.border_inactive" = lib.mkForce "rgba(8850ff5c)";

          groupbar = {
            "col.active" = lib.mkForce "rgb(b047ff)";
            "col.inactive" = lib.mkForce "rgba(8850ff5c)";
          };
        };

        animations.enabled = true;

        dwindle.preserve_split = true;

        master.new_status = "master";

        misc = {
          force_default_wallpaper = 0;
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

          sensitivity = 0;

          touchpad.natural_scroll = false;
        };
      };

      # curve/animation are separate top-level calls, not nested under `animations`
      # like hyprlang's `bezier =`/`animation =` keywords.
      curve = [
        {
          _args = [
            "easeOutQuint"
            {
              type = "bezier";
              points = [
                [
                  0.23
                  1
                ]
                [
                  0.32
                  1
                ]
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
                [
                  0.65
                  0.05
                ]
                [
                  0.36
                  1
                ]
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
                [
                  0
                  0
                ]
                [
                  1
                  1
                ]
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
                [
                  0.5
                  0.5
                ]
                [
                  0.75
                  1.0
                ]
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
                [
                  0.15
                  0
                ]
                [
                  0.1
                  1
                ]
              ];
            }
          ];
        }
      ];

      # `speed` is in deciseconds; the design system caps motion at 320ms (3.2).
      animation = [
        {
          leaf = "global";
          enabled = true;
          speed = 3.2;
          bezier = "default";
        }
        {
          leaf = "border";
          enabled = true;
          speed = 2; # border recolour is a state change: 200ms
          bezier = "easeOutQuint";
        }
        {
          leaf = "windows";
          enabled = true;
          speed = 3.2;
          bezier = "easeOutQuint";
        }
        # No popin `style` on window leaves: the theme avoids scale as motion.
        {
          leaf = "windowsIn";
          enabled = true;
          speed = 3.2;
          bezier = "easeOutQuint";
        }
        {
          leaf = "windowsOut";
          enabled = true;
          speed = 1.49;
          bezier = "linear";
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
          speed = 3.2;
          bezier = "easeOutQuint";
        }
        {
          leaf = "layersIn";
          enabled = true;
          speed = 3.2;
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

      # bindm/bindel/bindl don't exist as separate Lua functions -- their mouse/
      # locked/repeating flags are opts on hl.bind itself instead.
      bind = [
        (mkExecBind "${mainMod} + Q" terminal)
        (mkBind "${mainMod} + C" (dsp "hl.dsp.window.close()") null)
        (mkBind "${mainMod} + M" (dsp "hl.dsp.exit()") null)
        (mkExecBind "${mainMod} + E" fileManager)
        (mkBind "${mainMod} + V" (dsp "hl.dsp.window.float()") null)
        # Quickshell IPC flag order is `ipc -p <path> call <target> <fn>`.
        (mkExecBind "${mainMod} + R" "quickshell ipc -p ~/nix-dots/desktop/shell call launcher toggle")
        (mkExecBind "${mainMod} + T" "quickshell ipc -p ~/nix-dots/desktop/shell call theme next")
        # Chat overlay (qubi repo); K is an alias.
        (mkExecBind "${mainMod} + D" "quickshell ipc -p ~/nix-dots/desktop/shell call chat toggle")
        (mkExecBind "${mainMod} + K" "quickshell ipc -p ~/nix-dots/desktop/shell call chat toggle")
        # Reserved for qubi features not built yet; missing IPC targets exit 0 harmlessly.
        (mkExecBind "${mainMod} + U" "quickshell ipc -p ~/nix-dots/desktop/shell call clipboard transform")
        (mkExecBind "${mainMod} + I" "quickshell ipc -p ~/nix-dots/desktop/shell call screenctx capture")
        (mkExecBind "${mainMod} + N" "quickshell ipc -p ~/nix-dots/desktop/shell call notes capture")
        # Voice conversation overlay (qubi repo).
        (mkExecBind "${mainMod} + SHIFT + D" "quickshell ipc -p ~/nix-dots/desktop/shell call voice toggle")
        (mkBind "${mainMod} + P" (dsp "hl.dsp.window.pseudo()") null) # dwindle
        (mkBind "${mainMod} + J" (dsp "hl.dsp.layout(${toLua "togglesplit"})") null)
        (mkExecBind "${mainMod} + Z" editor)
        (mkExecBind "${mainMod} + F" browser)
        (mkExecBind "${mainMod} + A" claudeApp)
        (mkBind "${mainMod} + L" (dsp "hl.dsp.window.fullscreen()") null)

        (mkBind "${mainMod} + left" (dsp "hl.dsp.focus({ direction = \"left\" })") null)
        (mkBind "${mainMod} + right" (dsp "hl.dsp.focus({ direction = \"right\" })") null)
        (mkBind "${mainMod} + up" (dsp "hl.dsp.focus({ direction = \"up\" })") null)
        (mkBind "${mainMod} + down" (dsp "hl.dsp.focus({ direction = \"down\" })") null)
      ]
      ++ workspaceBinds
      ++ [
        (mkBind "${mainMod} + S" (dsp "hl.dsp.workspace.toggle_special(${toLua "magic"})") null)
        (mkBind "${mainMod} + SHIFT + S"
          (dsp "hl.dsp.window.move({ workspace = ${toLua "special:magic"} })")
          null
        )

        (mkBind "${mainMod} + mouse_down" (dsp "hl.dsp.focus({ workspace = ${toLua "e+1"} })") null)
        (mkBind "${mainMod} + mouse_up" (dsp "hl.dsp.focus({ workspace = ${toLua "e-1"} })") null)

        (mkBind "${mainMod} + mouse:272" (dsp "hl.dsp.window.drag()") { mouse = true; })
        (mkBind "${mainMod} + mouse:273" (dsp "hl.dsp.window.resize()") { mouse = true; })

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

        (mkBind "XF86AudioNext" (exec "playerctl next") { locked = true; })
        (mkBind "XF86AudioPause" (exec "playerctl play-pause") { locked = true; })
        (mkBind "XF86AudioPlay" (exec "playerctl play-pause") { locked = true; })
        (mkBind "XF86AudioPrev" (exec "playerctl previous") { locked = true; })

        # Print variants annotate in satty; SHIFT+Print goes straight to the clipboard.
        (mkExecBind "Print" "hyprshot -m region --raw | satty -f - -o ~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png --copy-command wl-copy")
        (mkExecBind "${mainMod} + Print" "hyprshot -m window --raw | satty -f - -o ~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png --copy-command wl-copy")
        (mkExecBind "${mainMod} + SHIFT + Print" "hyprshot -m output --raw | satty -f - -o ~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png --copy-command wl-copy")
        (mkExecBind "SHIFT + Print" "hyprshot -m region --clipboard-only")

        (mkExecBind "${mainMod} + SHIFT + C" "hyprpicker -a")

        # Eject the eGPU (amd.nix). Absolute systemctl path: the NOPASSWD rule matches
        # the exact string, so bare `systemctl` would prompt.
        (mkExecBind "${mainMod} + SHIFT + U" "sudo ${pkgs.systemd}/bin/systemctl start egpu-eject.service")

        # Nested gamescope Steam session; the start/stop wrappers (qubi-hwstate.nix)
        # evict Ollama from VRAM around it.
        (mkExecBind "${mainMod} + G" "ai-workstation-gaming-start && gamescope --steam -W 1920 -H 1080 -f -- steam ; ai-workstation-gaming-stop")

      ];
    };

    # Autostart is raw Lua: settings.exec-once generates invalid Lua under
    # configType = "lua" (nix-community/home-manager#9468).
    extraConfig = ''
      hl.on("hyprland.start", function()
          -- Quickshell draws the wallpaper and is the polkit agent, so don't also
          -- start hyprpaper or another polkit agent: they would conflict.
          -- The greeter-started session never sources hm-session-vars, so source
          -- it here or Quickshell lacks QUBI_SOCKET/QUBI_KNOWN_FOLDERS.
          hl.exec_cmd("sh -c 'unset __HM_SESS_VARS_SOURCED; . ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh; exec quickshell -p ~/nix-dots/desktop/shell'")
          hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
          -- Feeds cliphist, which Quickshell's clipboard-history widget reads.
          hl.exec_cmd("wl-paste --type text --watch cliphist store")
          hl.exec_cmd("wl-paste --type image --watch cliphist store")
      end)
    '';
  };
}
