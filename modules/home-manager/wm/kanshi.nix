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
        # One eGPU monitor plus the laptop screen. kanshi needs an exact output
        # match; without this, Hyprland's static docked position overlaps eDP-1.
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
        # Same as "egpu-samsung", with the Sceptre attached instead.
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
