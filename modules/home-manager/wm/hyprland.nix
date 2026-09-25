{ lib, pkgs, ... }:
let
  # hl.dsp.*/mkLuaInline mechanics and why `config` needs settings.config.*
  # instead of a top-level call: lib/hyprBinds.nix, hyprland-lua-configtype-pitfall memory.
  hyprBinds = import ../../../lib/hyprBinds.nix { inherit lib; };
  inherit (hyprBinds)
    dsp
    toLua
    exec
    mkBind
    mkExecBind
    ;

  mainMod = "SUPER"; # Sets "Windows" key as main modifier
  terminal = "ghostty";
  fileManager = "nautilus";
  claudeApp = "claude-desktop";
  editor = "zeditor";
  browser = "zen-twilight";

  workspaceBinds = hyprBinds.workspaceBinds mainMod;
in
{
  # satty's -o path (see screenshot binds below) doesn't create missing
  # parent directories itself.
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
        { _args = [ "XCURSOR_SIZE" "24" ]; }
        { _args = [ "XCURSOR_THEME" "XCursor-Pro-Dark" ]; }

        # Route Vulkan/OpenGL apps (Steam games) to the AMD eGPU (1002:73bf @ 0000:54:00.0)
        # when docked; MESA_VK_DEVICE_SELECT (Vulkan) + DRI_PRIME (OpenGL fallback).
        # Should fall through to the iGPU when undocked -- verify empirically, not confirmed against docs.
        { _args = [ "MESA_VK_DEVICE_SELECT" "1002:73bf" ]; }
        { _args = [ "DRI_PRIME" "0000:54:00.0" ]; }
      ];

      # general/decoration/animations/misc/render/cursor/input/dwindle/master
      # must nest under one hl.config({...}) call, not separate top-level calls.
      config = {
        general = {
          gaps_in = 2;
          gaps_out = 4;
          border_size = 1; # stroke-hairline
          # Flat dotted key, not nested `col = {...}`: must match stylix's own
          # hyprland module's attribute path exactly for mkForce to win the merge.
          #
          # Still a two-stop gradient, but BOTH stops are the same colour, so it
          # renders flat. Keeping the gradient shape (rather than collapsing to a
          # plain string) is deliberate twice over: it preserves the attribute
          # path stylix merges against above, and it matches the table shape
          # Theme.qml's syncHyprlandBorders() writes live via `hyprctl eval` on
          # every theme switch -- so the static config and the live one can't
          # drift into different shapes.
          "col.active_border" = lib.mkForce {
            colors = [
              "rgb(b047ff)" # line-strong
              "rgb(b047ff)"
            ];
            angle = 45;
          };
          "col.inactive_border" = lib.mkForce "rgba(8850ff5c)"; # line -- violet hairline
          resize_on_border = false;
          allow_tearing = false;
          layout = "dwindle";
        };

        # Ultraviolet is flat: depth comes from the surface stair and hairlines,
        # never from shadow, blur or opacity. Matches the shell's own radius
        # token (themes/ultraviolet-v2/theme.json radius.panel = 3) so the
        # compositor frame and the panels inside it share one bevel.
        decoration = {
          rounding = 3;
          rounding_power = 2;
          active_opacity = 1.0;
          inactive_opacity = 1.0; # was 0.85 -- opacity is not a hierarchy device

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

        # Grouped/tabbed windows are a separate colour namespace from
        # general.col.*_border -- stylix's own hyprland module (modules/
        # hyprland/hm.nix) sets these off base0D/base03, which is why the
        # inactive side came out grey (base03 = 212121) even after the main
        # border went violet. Flat dotted keys at the exact same attribute
        # path stylix uses (group."col.border_inactive", not a nested
        # `col = {...}`), same reasoning as general.col.active_border above.
        #
        # col.border_locked_active and groupbar.text_color are left alone:
        # stylix already puts the former on base0C (b047ff, already
        # correct) and the latter on base05 (body text grey, which is the
        # intended v2 colour for text anyway) -- forcing them would just
        # restate values that already match.
        group = {
          "col.border_active" = lib.mkForce "rgb(b047ff)"; # line-strong, matches general's active border
          "col.border_inactive" = lib.mkForce "rgba(8850ff5c)"; # line -- violet hairline, was rgb(212121)

          groupbar = {
            "col.active" = lib.mkForce "rgb(b047ff)";
            "col.inactive" = lib.mkForce "rgba(8850ff5c)"; # was rgb(212121)
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

      # Hyprland's `speed` is in DECISECONDS, so the design system's motion
      # caps read as: d-micro 120ms = 1.2, d-state 200ms = 2.0, d-surface
      # 320ms = 3.2. Nothing below is allowed past 3.2. Leaves already under
      # the cap (fades, workspaces, *Out) keep the values they had -- the cap
      # is a ceiling, not a target.
      animation = [
        {
          leaf = "global";
          enabled = true;
          speed = 3.2; # was 10
          bezier = "default";
        }
        {
          leaf = "border";
          enabled = true;
          speed = 2; # was 5.39 -- a border recolour is a state change
          bezier = "easeOutQuint";
        }
        {
          leaf = "windows";
          enabled = true;
          speed = 3.2; # was 4.79
          bezier = "easeOutQuint";
        }
        # No `style = "popin 87%"` on either leaf. Ultraviolet bans scale as a
        # motion device -- a window growing from 87% represents nothing
        # physical -- so windows fade instead. Omitting `style` entirely leaves
        # Hyprland on its own default (a plain slide/fade) rather than naming
        # one; this is the single most noticeable day-to-day change in the
        # restyle, and putting `style = "popin 87%";` back on both leaves is
        # the whole revert.
        {
          leaf = "windowsIn";
          enabled = true;
          speed = 3.2; # was 4.1
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
          speed = 3.2; # was 3.81
          bezier = "easeOutQuint";
        }
        {
          leaf = "layersIn";
          enabled = true;
          speed = 3.2; # was 4
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
      bind =
        [
          (mkExecBind "${mainMod} + Q" terminal)
          (mkBind "${mainMod} + C" (dsp "hl.dsp.window.close()") null)
          (mkBind "${mainMod} + M" (dsp "hl.dsp.exit()") null)
          (mkExecBind "${mainMod} + E" fileManager)
          (mkBind "${mainMod} + V" (dsp "hl.dsp.window.float()") null)
          # Quickshell launcher (quickshell/modules/launcher/) replaced Walker on SUPER+R
          # (walker.nix removed, recoverable at git tag pre-qubi-split). Shown/hidden via
          # Quickshell's own IPC, not exec/pkill -- flag order is `ipc -p <path> call <target> <fn>`.
          # Walker's rail/grid modes (old SHIFT+R/CTRL+R) have no equivalent and were dropped.
          (mkExecBind "${mainMod} + R" "quickshell ipc -p ~/nix-dots/quickshell call launcher toggle")
          # Cycles the active theme live via IPC, no restart.
          (mkExecBind "${mainMod} + T" "quickshell ipc -p ~/nix-dots/quickshell call theme next")
          # Chat overlay (see the qubi repo): talks to the `goose` CLI. D is primary, K an alias.
          (mkExecBind "${mainMod} + D" "quickshell ipc -p ~/nix-dots/quickshell call chat toggle")
          (mkExecBind "${mainMod} + K" "quickshell ipc -p ~/nix-dots/quickshell call chat toggle")
          # SUPER+H/B/X (session history/model browser/MCP manager) were dropped:
          # all reachable from inside the chat overlay itself, SUPER+D is the single entry point.
          # `quickshell ipc -p ~/nix-dots/quickshell call sessions toggle` still works manually.
          # Reserved for not-yet-built parallel-agent-branch features (target/function
          # calls fail gracefully today: "Target/Function not found.", exit 0):
          # clipboard-transform picker (see the qubi repo) -- U instead of X since X was taken above.
          (mkExecBind "${mainMod} + U" "quickshell ipc -p ~/nix-dots/quickshell call clipboard transform")
          # screen-context capture (see the qubi repo).
          (mkExecBind "${mainMod} + I" "quickshell ipc -p ~/nix-dots/quickshell call screenctx capture")
          # research -> TODO capture (see the qubi repo).
          (mkExecBind "${mainMod} + N" "quickshell ipc -p ~/nix-dots/quickshell call notes capture")
          # Voice conversation mode (see the qubi repo): straight into the full-screen overlay,
          # same IPC target as the chat panel's mic button. Defaults to the `fast` tier since
          # voice is back-and-forth where turnaround matters more than a reasoning trace.
          # (Side-by-side model comparison lost this slot to voice; still reachable from the
          # chat panel's hamburger menu, IPC target `chat compare` unchanged.)
          (mkExecBind "${mainMod} + SHIFT + D" "quickshell ipc -p ~/nix-dots/quickshell call voice toggle")
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
          # Special workspace (scratchpad)
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

          # hyprshot --raw pipes straight to satty on stdin for annotation (satty's own
          # Ctrl+S/Ctrl+C/Enter handle save/copy), skipping hyprshot's save/notify/clipboard path.
          # SHIFT+Print is the no-editor fast path: straight to clipboard, nothing touches disk.
          (mkExecBind "Print" "hyprshot -m region --raw | satty -f - -o ~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png --copy-command wl-copy")
          (mkExecBind "${mainMod} + Print" "hyprshot -m window --raw | satty -f - -o ~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png --copy-command wl-copy")
          (mkExecBind "${mainMod} + SHIFT + Print" "hyprshot -m output --raw | satty -f - -o ~/Pictures/Screenshots/satty-%Y%m%d-%H%M%S.png --copy-command wl-copy")
          (mkExecBind "SHIFT + Print" "hyprshot -m region --clipboard-only")

          # hyprpicker -a copies the picked colour straight to the
          # clipboard (autocopy) and exits -- no separate satty-style
          # annotate step needed for a plain colour pick.
          (mkExecBind "${mainMod} + SHIFT + C" "hyprpicker -a")

          # Gracefully eject the Thunderbolt eGPU (egpu-eject.service, modules/nixos/hardware/amd.nix).
          # Absolute systemctl path required: sudo's NOPASSWD rule matches the exact string,
          # a PATH-resolved bare `systemctl` falls through to an interactive prompt instead.
          (mkExecBind "${mainMod} + SHIFT + U" "sudo ${pkgs.systemd}/bin/systemctl start egpu-eject.service")

          # Steam + all games in one gamescope session (programs.steam.gamescopeSession,
          # games.nix), nested in this Hyprland session. ai-workstation-gaming-{start,stop}
          # (modules/home-manager/apps/goose.nix) evict Ollama from VRAM around the game.
          (mkExecBind "${mainMod} + G" "ai-workstation-gaming-start && gamescope --steam -W 1920 -H 1080 -f -- steam ; ai-workstation-gaming-stop")

        ];
    };

    # Autostart lives here, not `settings`: settings.exec-once generates invalid Lua under
    # configType = "lua" (nix-community/home-manager#9468) -- hl.on("hyprland.start", ...)
    # is the real event API, so this is raw Lua passed through as-is.
    extraConfig = ''
      hl.on("hyprland.start", function()
          -- Quickshell is the bar and launcher (SUPER+R); no waybar/elephant to start.
          -- hyprpaper dropped: quickshell/modules/wallpaper/Wallpaper.qml renders the
          -- Background layer for every theme now; running both would race the same output.
          -- hyprpaper package stays installed (modules/nixos/wm/hyprland.nix) as a fallback.
          --
          -- polkit-gnome-authentication-agent-1 no longer starts here --
          -- Quickshell registers its OWN polkit agent now
          -- (quickshell/modules/auth/PolkitAgentService.qml, mounted in
          -- shell.qml), confirmed live end-to-end: real pkexec-triggered
          -- flows render in AuthPromptWindow with real polkit/PAM message
          -- text, fingerprint races ahead of password exactly as
          -- /etc/pam.d/polkit-1 configures, and the window closes cleanly
          -- on cancel. Only one agent can hold the session's polkit slot at
          -- a time, so running both would conflict -- see
          -- PolkitAgentService.qml's own header for that detail and for
          -- why its D-Bus path includes a per-instance suffix (registration
          -- silently fails to survive a plain hot-reload at a fixed path).
          hl.exec_cmd("quickshell -p ~/nix-dots/quickshell")
          hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
          -- Clipboard history: cliphist's own db, fed by every wl-copy
          -- (including the hyprshot/satty --copy-command paths above and
          -- hyprpicker -a). Quickshell's clipboard-history widget reads
          -- `cliphist list`/`cliphist decode` against this same db.
          hl.exec_cmd("wl-paste --type text --watch cliphist store")
          hl.exec_cmd("wl-paste --type image --watch cliphist store")
      end)
    '';
  };
}
