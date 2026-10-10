{
  mkUserModule,
  forPlatform,
  lib,
  pkgs,
  ...
}:
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

  system.programs.ssh = {
    extraConfig = ''
      Host *
        IdentityAgent "${
          forPlatform {
            darwin = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
            linux = "~/.1password/agent.sock";
          }
        }"

      Match host polaris exec "${pkgs.coreutils}/bin/timeout 1 ${pkgs.netcat}/bin/nc -z polaris.local 22"
        HostName polaris.local
    '';
  };

  # `polaris` resolves through MagicDNS to its tailnet address. On the home LAN
  # the Match above swaps in its mDNS name (avahi, modules/linux/network.nix),
  # so traffic stays local instead of going through tailscale. The probe is
  # capped at 1s because a failed .local lookup otherwise blocks ~5s off-LAN.
  # Names, not addresses: a node re-added to the tailnet or re-leased by DHCP keeps its
  # name. (If MagicDNS is ever off, the tailnet address is 100.123.15.108.)
  #
  # Getting a shell on polaris is the tmux picker's job (tmux `peers`), which
  # hops this terminal into polaris's tmux instead of nesting it.
}
