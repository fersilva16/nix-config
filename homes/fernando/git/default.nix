{ ... }:
{
  programs.git = {
    enable = true;

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

    userEmail = "fernandonsilva16@gmail.com";
    userName = "Fernando Silva";
  };
}
