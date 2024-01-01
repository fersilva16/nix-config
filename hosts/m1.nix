{ pkgs, ... }:
{
  imports = [
    ./common/caskaydia-cove.nix
  ];

  environment.etc = {
    "pam.d/sudo_local" = {
      text = ''
        auth       sufficient     pam_tid.so
      '';
    };
  };

  nix = {
    package = pkgs.nixUnstable;

    useDaemon = true;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
