{ username, ... }:
let configDir = "Library/Application Support/Code/User";
in {
  homebrew.casks = [ "visual-studio-code" ];

  home-manager.users.${username} = {
    home.file."${configDir}/settings.json" = {
      source = ./settings.json;
      force = true;
    };
  };
}
