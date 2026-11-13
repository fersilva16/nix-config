{
  mkUserModule,
  forPlatform,
  fleetPeers,
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
    let
      agent = forPlatform {
        darwin = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
        linux = "~/.1password/agent.sock";
      };
      sshPeers = lib.attrNames (lib.filterAttrs (_: peer: lib.elem "ssh" peer.services) fleetPeers);
      # The agent forwarded in by the latest SSH login (modules/cli/ssh.nix).
      # While that login lives, it signs and forwards instead of the local
      # 1Password, so a rebuild started from vega asks on vega, not on a
      # screen nobody watches. Its socket goes when the login ends.
      forwarded = "~/.ssh/agent.sock";
      # exec runs through the user's shell; %d hands it an absolute path.
      live = ''exec "${pkgs.coreutils}/bin/test -S %d/.ssh/agent.sock"'';
      forwardedFirst = forPlatform {
        linux =
          lib.optionalString (sshPeers != [ ]) ''
            Match host ${lib.concatStringsSep "," sshPeers} ${live}
              ForwardAgent ${forwarded}
          ''
          + ''
            Match ${live}
              IdentityAgent ${forwarded}
          '';
      };
    in
    lib.recursiveUpdate
      {
        # ssh uses the 1Password agent, and forwards it to fleet peers. Only
        # where 1Password runs: IdentityAgent beats $SSH_AUTH_SOCK, so on a
        # host without it (altair) ssh would ignore the agent forwarded in.
        # mkBefore: ssh takes the first value it reads, and modules/cli/ssh.nix
        # sets `ForwardAgent yes` for the same peers.
        programs.ssh.extraConfig = lib.mkBefore (
          forwardedFirst
          + lib.optionalString (sshPeers != [ ]) ''
            Host ${lib.concatStringsSep " " sshPeers}
              ForwardAgent "${agent}"
          ''
          + ''
            Host *
              IdentityAgent "${agent}"
          ''
        );
      }
      (forPlatform {
        linux = {
          programs._1password.enable = true;
          programs._1password-gui = {
            enable = true;
            polkitPolicyOwners = builtins.attrNames enabledUsers;
          };
        };
      });
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

      # Start 1Password minimized to the tray at niri login so the SSH agent
      # and browser integration are ready. `or false`: the niri option only
      # exists on linux hosts (darwin discovery skips modules/linux).
      xdg.configFile = lib.mkIf (userCfg.niri.enable or false) {
        "niri/config.kdl".text = ''
          spawn-at-startup "1password" "--silent"
        '';
      };
    };
}
