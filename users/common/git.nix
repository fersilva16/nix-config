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
      user = {
        signingkey = "A18F5120B7AC3113";
      };

      commit = {
        gpgsign = true;
      };

      init.defaultBranch = "main";

      pull.rebase = false;

      push.autoSetupRemote = true;
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
