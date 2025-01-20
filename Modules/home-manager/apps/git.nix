{ ... }:

{
  programs = {
    git = {
      enable = true;
      userName = "cryptix";
      userEmail = "cryptixmc@proton.me";
      aliases = {
        pu = "push";
        co = "checkout";
        cm = "commit";
      };
    };
  };
}
