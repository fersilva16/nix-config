{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [ paisa ];

    home.file."Documents/paisa/paisa.yaml" = {
      source = ./paisa.yaml;
      force = true;
    };
  };
}
