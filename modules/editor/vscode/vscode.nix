{ mkUserModule, ... }:
let
  configDir = "Library/Application Support/Code/User";
in
mkUserModule {
  name = "vscode";
  system.homebrew.casks = [ "visual-studio-code" ];
  home = {
    home.file."${configDir}/settings.json" = {
      source = ./settings.json;
      force = true;
    };
  };
}
