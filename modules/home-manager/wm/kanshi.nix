{ ... }:
{
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "Samsung Electric Company LF24T35 H1AK500000*";
            status = "enable";
            mode = "1920x1080";
            position = "0,420";
            transform = "normal";
          }
          {
            criteria = "Sceptre Tech Inc Sceptre C24*";
            status = "enable";
            mode = "1920x1080";
            position = "1920,0";
            transform = "270";
          }
          {
            criteria = "AU Optronics 0xFA9B*";
            status = "disable";
          }
        ];
      }
      {
        # Single eGPU monitor (not the full two-monitor desk dock) + laptop
        # screen still active: kanshi requires an exact match of connected
        # outputs, so neither "docked" (needs both desk monitors) nor
        # "laptop" (laptop only) applies here -- without this, Hyprland
        # falls back to hyprland.nix's static DP-6 position (0,420), tuned
        # for the docked layout where eDP-1 is off, which overlaps eDP-1
        # once it's on. Sit the external monitor directly above instead.
        profile.name = "egpu-samsung";
        profile.outputs = [
          {
            criteria = "Samsung Electric Company LF24T35 H1AK500000*";
            status = "enable";
            mode = "1920x1080";
            position = "0,-1080";
            transform = "normal";
          }
          {
            criteria = "AU Optronics 0xFA9B*";
            status = "enable";
            mode = "1920x1200";
            position = "0,0";
          }
        ];
      }
      {
        # Same as "egpu-samsung" above, for when the Sceptre is the one
        # plugged into the eGPU alone instead.
        profile.name = "egpu-sceptre";
        profile.outputs = [
          {
            criteria = "Sceptre Tech Inc Sceptre C24*";
            status = "enable";
            mode = "1920x1080";
            position = "0,-1080";
            transform = "normal";
          }
          {
            criteria = "AU Optronics 0xFA9B*";
            status = "enable";
            mode = "1920x1200";
            position = "0,0";
          }
        ];
      }
      {
        profile.name = "laptop";
        profile.outputs = [
          {
            criteria = "AU Optronics 0xFA9B*";
            status = "enable";
            mode = "1920x1200";
            position = "0,0";
          }
        ];
      }
    ];
  };
}
