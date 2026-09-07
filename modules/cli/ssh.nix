{
  mkUserModule,
  forPlatform,
  lib,
  ...
}:
mkUserModule {
  name = "ssh";

  extraOptions.authorizedKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Public keys accepted for SSH login as this user.";
  };

  # linux only: on darwin the daemon is toggled ad hoc by tmux-remote and the
  # keys are handed out by the 1Password agent, so there is no declarative
  # authorized_keys to own there. forPlatform yields {} on darwin.
  user =
    { cfg, ... }:
    forPlatform {
      linux.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

  system.programs.ssh = {
    extraConfig = ''
      Host *
        IdentityAgent "${
          forPlatform {
            darwin = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
            linux = "~/.1password/agent.sock";
          }
        }"
    '';
  };

  # There is deliberately no `Host polaris` block: MagicDNS already resolves the
  # node's tailnet name, so an ssh_config entry would only restate it. That also
  # makes this self-healing — a node re-added to the tailnet keeps its name but
  # not its address. (If MagicDNS is ever off, the node address is
  # 100.123.15.108; hardcoding that is the fallback, not the default.)
  #
  # `polaris` lands straight in polaris's tmux, so the session survives the link
  # dropping — the whole point of tmux on a box reached over the network.
  # tmux-attach is the same entrypoint ghostty uses locally.
  #
  # It also opens a SOCKS5 proxy on 127.0.0.1:1080 that egresses from polaris.
  # That is a convenience (a route out through the house), NOT the way this
  # machine reaches the tailnet — reaching polaris is the precondition for the
  # proxy, so it cannot also be the means. Point clients at it with
  # `--socks5-hostname` (curl) or ProxyCommand (ssh) so names resolve on the
  # polaris side. It is a full proxy, not a tailnet-only route: anything aimed
  # at 1080 leaves via the house rather than via WARP.
  home =
    { userCfg, ... }:
    {
      programs.fish.shellAliases = lib.mkIf userCfg.fish.enable {
        polaris = "ssh -D 1080 -t polaris tmux-attach";
      };
    };
}
