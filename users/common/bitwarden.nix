{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bitwarden-cli
    jq
  ];

  programs.rbw = {
    enable = true;

    settings = {
      email = "fernando457829@gmail.com";
      pinentry = "tty";
    };
  };
}

