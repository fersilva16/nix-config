{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;

    package = pkgs.gitAndTools.gitFull;

    extraConfig = {
      gpg = {
        program = "/opt/homebrew/bin/gpg";
      };

      user = {
        signingkey = "05623174D690C511";
      };

      commit = {
        gpgsign = true;
      };

      init.defaultBranch = "main";

      pull.rebase = false;

      push.autoSetupRemote = true;

      core.ignorecase = false;
    };

    userEmail = "fernandonsilva16@gmail.com";
    userName = "Fernando Silva";
  };

  home.packages = with pkgs; [
    gh
  ];

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };
}
