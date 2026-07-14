{ mkUserModule, ... }:
mkUserModule {
  name = "flameshot";
  home = {
    services.flameshot.enable = true;
  };
}
