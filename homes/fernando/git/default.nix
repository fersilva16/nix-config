{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    package = pkgs.gitAndTools.gitFull;

    aliases = {
      b = "branch";
      co = "checkout";
      cm = "commit -m";
      p = "push";
    };

    extraConfig = {
      init.defaultBranch = "main";
    };

    # TODO: setup signing

    pull.rebase = false;

    userEmail = "fernandonsilva16@gmail.com";
    userName = "Fernando Silva";
  };

  program.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };
}
