{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
mkUserModule {
  name = "1password";
  requires = [ "git" ];
  casks = [
    "1password"
    "1password-cli"
  ];
  # On linux the GUI + CLI come from nixpkgs; polkit integration needs the
  # enabling users listed so system authentication prompts work.
  system =
    { enabledUsers }:
    forPlatform {
      linux = {
        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = builtins.attrNames enabledUsers;
        };
      };
    };
  home =
    { userCfg, ... }:
    {
      # Git SSH signing via 1Password
      programs.git.settings = lib.mkIf userCfg.git.enable {
        user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYJzdB1rfmSCEOISYTmGcSi43YD+bzTuPAad98IQOuc";
        gpg.format = "ssh";
        "gpg \"ssh\"".program = forPlatform {
          darwin = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
          linux = lib.getExe' pkgs._1password-gui "op-ssh-sign";
        };
        commit.gpgsign = true;
      };
    };
}
