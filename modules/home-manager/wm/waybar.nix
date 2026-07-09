{ ... }:

{
  programs.waybar = {
    enable = true;

    settings = [
      {
        layer = "top";
        position = "top";
        height = 26;
        spacing = 0;
        fixed-center = true;

        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "network"
          "battery"
          "backlight"
          "pulseaudio"
          "custom/bluetooth"
          "temperature"
          "custom/notifications"
        ];

        "hyprland/workspaces" = {
          format = "●";
          on-click = "activate";
          active-only = false;
          persistent-workspaces = {
            "*" = 5;
          };
        };

        "hyprland/window" = {
          format = "{}";
          max-length = 60;
          separate-outputs = true;
        };

        clock = {
          format = "{:%I:%M %p · %a %d}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "month";
            on-scroll = 1;
            format = {
              months = "<b>{}</b>";
              today = "<b><u>{}</u></b>";
            };
          };
        };

        network = {
          interval = 2;
          format-wifi = "󰤨";
          format-ethernet = "󰈀";
          format-disconnected = "󰤭";
          format-linked = "󰤫";
          tooltip-format-wifi = "<span size='small' color='#b047ff'>NETWORK</span>\n{essid}\n<span size='small' color='#505050'>{ipaddr} · ↑{bandwidthUpBytes} ↓{bandwidthDownBytes}</span>";
          tooltip-format-ethernet = "<span size='small' color='#b047ff'>NETWORK</span>\n{ifname}\n<span size='small' color='#505050'>{ipaddr}</span>";
          tooltip-format-disconnected = "<span size='small' color='#b047ff'>NETWORK</span>\ndisconnected";
          on-click = "ghostty -e nmtui";
        };

        battery = {
          bat = "BAT0";
          adapter = "AC";
          interval = 30;
          format = "{icon}";
          format-charging = "󰂄";
          format-plugged = "󰚥";
          format-full = "󰁹";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];

          tooltip-format = "<span size='small' color='#b047ff'>BATTERY</span>\n{capacity}%\n<span size='small' color='#505050'>discharging · ~{time}</span>";
          tooltip-format-charging = "<span size='small' color='#b047ff'>BATTERY</span>\n{capacity}%\n<span size='small' color='#505050'>charging</span>";
          tooltip-format-plugged = "<span size='small' color='#b047ff'>BATTERY</span>\n{capacity}%\n<span size='small' color='#505050'>plugged in</span>";
          tooltip-format-full = "<span size='small' color='#b047ff'>BATTERY</span>\n{capacity}%\n<span size='small' color='#505050'>full</span>";

          states = {
            warning = 30;
            critical = 15;
          };
        };

        backlight = {
          format = "{icon}";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
          ];
          tooltip-format = "<span size='small' color='#b047ff'>BRIGHTNESS</span>\n{percent}%";
          on-scroll-up = "brightnessctl set +5%";
          on-scroll-down = "brightnessctl set 5%-";
        };

        pulseaudio = {
          format = "{icon}";
          format-muted = "󰝟";
          format-icons = {
            default = [
              "󰕿"
              "󰖀"
              "󰕾"
            ];
            headphone = [ "󰋋" ];
            headset = [ "󰋎" ];
          };
          tooltip-format = "<span size='small' color='#b047ff'>VOLUME</span>\n{volume}%\n<span size='small' color='#505050'>{desc}</span>";
          on-click = "pavucontrol";
          on-scroll-up = "pactl set-sink-volume @DEFAULT_SINK@ +5%";
          on-scroll-down = "pactl set-sink-volume @DEFAULT_SINK@ -5%";
          scroll-step = 5;
        };

        "custom/bluetooth" = {
          format = "󰂯";
          tooltip = true;
          tooltip-format = "<span size='small' color='#b047ff'>BLUETOOTH</span>\nConnected\n<span size='small' color='#505050'>devices active</span>";
          on-click = "blueman-manager";
        };

        temperature = {
          interval = 5;
          format = "{icon}";
          format-icons = [
            "󱃃"
            "󰔏"
            "󱃂"
          ];
          format-critical = "󰸁";
          tooltip-format = "<span size='small' color='#b047ff'>CPU TEMP</span>\n{temperatureC}°C\n<span size='small' color='#505050'>normal</span>";
          critical-threshold = 80;
        };

        "custom/notifications" = {
          format = "󰂚";
          tooltip = true;
          tooltip-format = "<span size='small' color='#b047ff'>NOTIFICATIONS</span>\nrunning\n<span size='small' color='#505050'>dnd: off</span>";
        };
      }
    ];

    style = ''
      /* ── Ultraminimal Design System ── */
      * {
        font-family: "JetBrains Mono", "JetBrainsMono Nerd Font", monospace;
        font-size: 13px;
        border: none;
        border-radius: 0;
        min-height: 0;
        padding: 0;
        margin: 0;
      }

      window#waybar {
        background: rgba(5, 5, 5, 0.92);
        border-bottom: 1px solid rgba(33, 33, 33, 0.6);
        color: #c8c8c8;
      }

      /* ── Workspaces (Circle Dots) ── */
      #workspaces {
        padding: 0 4px 0 12px;
      }

      #workspaces button {
        background: transparent;
        border: none;
        border-radius: 0;
        box-shadow: none;
        padding: 0;
        color: rgba(255, 255, 255, 0.07);
        transition: color 180ms ease-out, text-shadow 180ms ease-out;
      }

      #workspaces button label {
        font-size: 8px;
        padding: 0 3px;
        min-width: 0;
        min-height: 0;
      }

      #workspaces button.active {
        color: #ff5de0;
        text-shadow: 0 0 5px rgba(255, 93, 224, 0.52);
      }

      #workspaces button.occupied {
        color: rgba(200, 200, 200, 0.45);
      }

      #workspaces button:hover {
        color: #ff5de0;
      }

      /* ── Separator ── */
      #window {
        font-size: 11px;
        color: rgba(200, 200, 200, 0.55);
        letter-spacing: 0.06em;
        padding-left: 7px;
        border-left: 1px solid rgba(255, 255, 255, 0.07);
        margin-left: 7px;
        margin-top: 13px;
        margin-bottom: 13px;
      }

      /* ── Clock ── */
      #clock {
        font-size: 11px;
        color: rgba(200, 200, 200, 0.65);
        letter-spacing: 0.09em;
        padding: 0;
      }

      /* ── Right-Side Modules ── */
      #network,
      #battery,
      #backlight,
      #pulseaudio,
      #custom-bluetooth,
      #temperature,
      #custom-notifications {
        min-width: 22px;
        min-height: 22px;
        padding: 0;
        color: rgba(200, 200, 200, 0.52);
        transition: color 180ms ease-out;
      }

      #network:hover,
      #battery:hover,
      #backlight:hover,
      #pulseaudio:hover,
      #custom-bluetooth:hover,
      #temperature:hover,
      #custom-notifications:hover {
        color: rgba(176, 71, 255, 0.88);
      }

      /* Critical animations */
      #battery.critical,
      #temperature.critical {
        color: #ff5de0;
        animation: blink 1s step-end infinite;
      }

      @keyframes blink {
        0%   { opacity: 1; }
        50%  { opacity: 0.2; }
        100% { opacity: 1; }
      }

      /* ── Tooltips ── */
      tooltip {
        background: rgba(6, 6, 9, 0.98);
        border: 1px solid rgba(33, 33, 33, 0.95);
        border-radius: 6px;
        padding: 9px 11px;
        box-shadow: 0 8px 28px rgba(0, 0, 0, 0.78);
        min-width: 138px;
      }

      tooltip label {
        font-family: "JetBrains Mono", monospace;
        font-size: 11px;
        color: rgba(245, 245, 245, 0.8);
        padding: 1px 0;
      }
    '';
  };
}
