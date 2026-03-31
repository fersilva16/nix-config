{ mkUserModule, ... }:
mkUserModule {
  name = "zoxide";
  home = {
    programs.zoxide = {
      enable = true;

      enableFishIntegration = true;

      options = [
        "--cmd=cd"
      ];
    };
  };
}
