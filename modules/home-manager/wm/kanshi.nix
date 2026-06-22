{ ... }:
{
  services.kanshi = {
    enable = true;
    profiles = {
      docked = {
        outputs = [
          {
            criteria = "Samsung Electric Company LF24T35 H1AK500000";
            status = "enable";
            mode = "1920x1080";
            position = "0,420";
            transform = "normal";
          }
          {
            criteria = "Sceptre Tech Inc Sceptre C24";
            status = "enable";
            mode = "1920x1080";
            position = "1920,0";
            transform = "270";
          }
          {
            criteria = "AU Optronics 0xFA9B";
            status = "disable";
          }
        ];
      };
      laptop = {
        outputs = [
          {
            criteria = "AU Optronics 0xFA9B";
            status = "enable";
            mode = "1920x1200";
            position = "0,0";
          }
        ];
      };
    };
  };
}
