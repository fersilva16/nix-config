{
  mkUserModule,
  lib,
  ...
}:
mkUserModule {
  name = "1password";
  requires = [ "git" ];
  system.homebrew.casks = [
    "1password"
    "1password-cli"
  ];
  home =
    { userCfg, ... }:
    {
      # Git SSH signing via 1Password
      programs.git.settings = lib.mkIf userCfg.git.enable {
        user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYJzdB1rfmSCEOISYTmGcSi43YD+bzTuPAad98IQOuc";
        gpg.format = "ssh";
        "gpg \"ssh\"".program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
        commit.gpgsign = true;
      };
    };
}
