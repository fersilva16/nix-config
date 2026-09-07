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
}
