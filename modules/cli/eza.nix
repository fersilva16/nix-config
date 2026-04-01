{
  mkUserModule,
  lib,
  ...
}:
mkUserModule {
  name = "eza";
  home =
    { userCfg, ... }:
    {
      programs.eza.enable = true;
      programs.fish.shellAliases = lib.mkIf userCfg.fish.enable {
        ls = "eza -lag";
      };
    };
}
