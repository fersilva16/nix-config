{ mkUserModule, lib, ... }:
mkUserModule {
  name = "chrome-cli";
  system.homebrew.brews = [ "chrome-cli" ];
  home =
    { userCfg, ... }:
    {
      programs.fish.functions = lib.mkIf userCfg.fish.enable {
        dia-cli = {
          wraps = "chrome-cli";
          description = "chrome-cli wrapper for Dia browser";
          body = "env CHROME_BUNDLE_IDENTIFIER=company.thebrowser.dia chrome-cli $argv";
        };
      };
    };
}
