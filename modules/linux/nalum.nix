# nalum — the account the personal Nalum (and the agents it runs) live in,
# apart from fernando.
#
# A normal user with its own home and group, no sudo (not in wheel) and no
# password: the hash is locked, so it logs in only with an SSH key. sshd
# still takes keys for it, since NixOS runs sshd through PAM, which does not
# treat a locked password as a locked account.
#
# Each host makes nalum's own SSH key on its first boot or activation, as
# nalum, so the private half never leaves the host and never needs fernando's
# 1Password agent (which refuses while his Mac is locked). The public half is
# committed as keys/nalum-<host>.nix once it exists; a host lets the nalum of
# each peer in `sshFrom` log in as its own nalum.
#
# `power` lets group nalum, and `power.users`, suspend, hibernate, power off
# and reboot through logind with no password, from any session (ssh
# included): `ssh polaris systemctl suspend`. Inhibitor locks still hold:
# the *-ignore-inhibit actions are not granted.
{
  mkSystemModule,
  lib,
  pkgs,
  ...
}:
let
  name = "nalum";
  home = "/home/${name}";
  key = "${home}/.ssh/id_ed25519";
  keyFile = host: ../../keys/nalum-${host}.nix;

  logindActions =
    lib.concatMap
      (action: [
        "org.freedesktop.login1.${action}"
        "org.freedesktop.login1.${action}-multiple-sessions"
      ])
      [
        "suspend"
        "hibernate"
        "power-off"
        "reboot"
      ];
in
mkSystemModule {
  inherit name;

  extraOptions = {
    sshFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Fleet peers whose nalum may SSH in as this host's nalum (keys/nalum-<peer>.nix).";
    };
    power = {
      enable = lib.mkEnableOption "passwordless suspend, hibernate, power-off and reboot for group nalum";
      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Users outside group nalum that get the same power actions.";
      };
    };
  };

  config =
    { config, cfg, ... }:
    let
      # A peer's key exists only after that peer's first activation, so a
      # peer listed before its key is committed is skipped with a warning.
      missing = lib.filter (host: !builtins.pathExists (keyFile host)) cfg.sshFrom;
      present = lib.subtractLists missing cfg.sshFrom;
    in
    lib.mkMerge [
      {
        users = {
          users.${name} = {
            isNormalUser = true;
            group = name;
            inherit home;
            hashedPassword = "!";
            openssh.authorizedKeys.keys = lib.concatMap (host: import (keyFile host)) present;
          };
          groups.${name} = { };
        };

        warnings = map (
          host:
          "modules.system.nalum.sshFrom: keys/nalum-${host}.nix is not committed yet, so nalum@${host} cannot log in."
        ) missing;

        systemd.services.nalum-ssh-key = {
          description = "nalum's SSH key on ${config.networking.hostName}";
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = home;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = name;
            Group = name;
          };
          # ssh-keygen writes the private key 0600 and the public one 0644.
          script = ''
            if [ ! -e ${key} ]; then
              install -d -m 0700 ${home}/.ssh
              ${config.programs.ssh.package}/bin/ssh-keygen -q -t ed25519 -N "" \
                -C "${name}@${config.networking.hostName}" -f ${key}
            fi
          '';
        };
      }

      (lib.mkIf cfg.power.enable {
        security.polkit = {
          enable = true;
          extraConfig = ''
            polkit.addRule(function (action, subject) {
              var actions = ${builtins.toJSON logindActions};
              var users = ${builtins.toJSON cfg.power.users};
              if (actions.indexOf(action.id) >= 0 &&
                  (subject.isInGroup("${name}") || users.indexOf(subject.user) >= 0)) {
                return polkit.Result.YES;
              }
            });
          '';
        };
      })
    ];
}
