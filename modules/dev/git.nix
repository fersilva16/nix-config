{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    programs.git = {
      enable = true;
      lfs.enable = true;

      package = pkgs.git;

      settings = {
        user = {
          email = "fernandonsilva16@gmail.com";
          name = "Fernando Silva";
          signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYJzdB1rfmSCEOISYTmGcSi43YD+bzTuPAad98IQOuc";
        };

        gpg = {
          format = "ssh";
        };

        "gpg \"ssh\"" = {
          program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
        };

        commit = {
          gpgsign = true;
        };

        init = {
          defaultBranch = "main";
        };

        pull = {
          rebase = false;
        };

        push = {
          autoSetupRemote = true;
        };

        core = {
          ignorecase = false;
        };
      };
    };

    home.packages = with pkgs; [ gh ];

    programs.gh = {
      enable = true;
      settings.git_protocol = "ssh";
    };
  };
}
