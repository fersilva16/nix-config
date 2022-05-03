{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixUnstable;

    settings = {
      trusted-users = [ "root" "@wheel" ];
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      options = "--delete-older-than 15d";
    };

    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
      keep-derivations = true
    '';
  };

  environment = {
    loginShellInit = ''
      [ -d "$HOME/.nix-profile" ] || /nix/var/nix/profiles/per-user/$USER/home-manager/activate &> /dev/null
    '';
    homeBinInPath = true;
    localBinInPath = true;

    etc."nixos" = {
      target = "nixos";
      source = "/dotfiles";
    };
  };

  home-manager.users.root.programs.git = {
    enable = true;
    extraConfig.safe.directory = "/dotfiles";
  };
}
