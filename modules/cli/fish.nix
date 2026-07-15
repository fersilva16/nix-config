{
  mkUserModule,
  forPlatform,
  pkgs,
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

      # HM generates completions by parsing every package's man pages; the
      # parser chokes on some of them (bat 0.26.1 on nixos-unstable broke the
      # polaris install build). Packages ship real completions via
      # vendor_completions.d anyway — the scraped ones aren't worth the
      # build fragility.
      generateCompletions = false;

      interactiveShellInit = ''
        ${forPlatform { darwin = "ssh-add --apple-load-keychain 2> /dev/null"; }}

        set fish_cursor_default block
        set fish_cursor_insert line
        set -U fish_greeting

        ${forPlatform {
          # PATH juggling is darwin-only: nix paths must beat /usr/bin and
          # homebrew there. NixOS orders PATH correctly natively — and moving
          # /run/current-system/sw/bin forward on linux shadows the setuid
          # sudo in /run/wrappers/bin ("sudo: must be owned by uid 0").
          darwin = ''
            fish_add_path -amP /usr/bin
            fish_add_path -amP /opt/homebrew/bin
            fish_add_path -amP /opt/local/bin
            fish_add_path -m /run/current-system/sw/bin
            fish_add_path -m ~/.nix-profile/bin
          '';
        }}
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
