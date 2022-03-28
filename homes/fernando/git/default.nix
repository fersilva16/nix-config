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

      credential.helper = "cache --timeout=7200";
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
