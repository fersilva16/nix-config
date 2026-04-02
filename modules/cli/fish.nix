{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "fish";
  user = _: {
    shell = pkgs.fish;
  };
  system = {
    environment = {
      systemPackages = [ pkgs.fish ];
      shells = [ pkgs.fish ];
    };

    programs.fish.enable = true;
  };
  home = {
    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        ssh-add --apple-load-keychain 2> /dev/null

        set fish_cursor_default block
        set fish_cursor_insert line
        set -U fish_greeting

        fish_add_path -amP /usr/bin
        fish_add_path -amP /opt/homebrew/bin
        fish_add_path -amP /opt/local/bin
        fish_add_path -m /run/current-system/sw/bin
        fish_add_path -m /Users/fernando/.nix-profile/bin
      '';

      functions = {
        fish_command_not_found = "__fish_default_command_not_found_handler $argv";

        envsource = ''
          for line in (cat $argv | grep -v '^#' | grep -v '^\s*$')
            set item (string trim $line | string replace -r '\s*=\s*' '=' | string split -m 1 '=')
            set -gx $item[1] $item[2]
            echo \"Exported key $item[1]\"
          end
        '';
      };
    };
  };
}
