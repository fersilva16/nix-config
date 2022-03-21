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

      pull.rebase = false;
    };

    # TODO: setup signing

    userEmail = "fernandonsilva16@gmail.com";
    userName = "Fernando Silva";
  };

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };
}
