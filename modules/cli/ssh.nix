{
  mkUserModule,
  forPlatform,
  lib,
  pkgs,
  fleetPeers,
  ...
}:
let
  onePasswordAgent = forPlatform {
    darwin = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
    linux = "~/.1password/agent.sock";
  };

  sshPeers = lib.filterAttrs (_: peer: lib.elem "ssh" peer.services) fleetPeers;
in
mkUserModule {
  name = "ssh";

  extraOptions.authorizedKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Public keys accepted for SSH login as this user.";
  };

  # linux only: on darwin the daemon is left to Remote Login and the
  # keys are handed out by the 1Password agent, so there is no declarative
  # authorized_keys to own there. forPlatform yields {} on darwin.
  user =
    { cfg, ... }:
    forPlatform {
      linux.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

  system = {
    programs.ssh.extraConfig = ''
      Host *
        IdentityAgent "${onePasswordAgent}"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: _: ''

        Match host ${name} exec "${pkgs.coreutils}/bin/timeout 1 ${pkgs.netcat}/bin/nc -z ${name}.local 22"
          HostName ${name}.local

        Host ${name}
          ForwardAgent "${onePasswordAgent}"
      '') sshPeers
    );
  }
  # sudo over SSH is approved by the forwarded agent: pam_ssh_agent_auth asks
  # it to sign with a key from /etc/ssh/authorized_keys.d/<user> (the
  # authorizedKeys above), and 1Password on the far end gates that signature
  # behind Touch ID. No agent, or a refused prompt, falls through to the
  # password. NixOS adds `env_keep+=SSH_AUTH_SOCK` to sudoers for it.
  // forPlatform {
    linux.security.pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
  };

  # Shells outlive SSH connections (polaris's tmux survives every hop), so the
  # per-connection socket they inherited goes stale. sshd runs ~/.ssh/rc on
  # each login: it repoints a fixed symlink at the live socket, and fish always
  # uses the symlink. The latest interactive connection with an agent wins;
  # SSH_TTY keeps one-shot `ssh polaris cmd`/scp logins from repointing it at
  # a socket that disappears seconds later.
  home =
    { userCfg, ... }:
    forPlatform {
      linux = {
        home.file.".ssh/rc".text = ''
          if [ -n "$SSH_TTY" ] && [ -S "$SSH_AUTH_SOCK" ]; then
            ${pkgs.coreutils}/bin/ln -sfn "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"
          fi
        '';
        programs.fish.interactiveShellInit = lib.mkIf userCfg.fish.enable ''
          set -gx SSH_AUTH_SOCK ~/.ssh/agent.sock
        '';
      };
    };

  # Every fleet peer that advertises "ssh" (modules/system/fleet.nix) gets a block.
  # A bare name resolves through MagicDNS to its tailnet address. On the home LAN
  # the Match above swaps in its mDNS name (avahi, modules/linux/network.nix),
  # so traffic stays local instead of going through tailscale. The probe is
  # capped at 1s because a failed .local lookup otherwise blocks ~5s off-LAN.
  # Names, not addresses: a node re-added to the tailnet or re-leased by DHCP keeps its
  # name.
  #
  # ForwardAgent names the 1Password socket because `yes` would forward
  # $SSH_AUTH_SOCK, which on darwin is launchd's agent, not IdentityAgent.
  #
  # Getting a shell on polaris is the tmux picker's job (tmux `peers`), which
  # hops this terminal into polaris's tmux instead of nesting it.
}
