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
#
# `agents` runs Nalum's coding agents as nalum on this host
# (limi specs/2026_11_16_nalums-coding-agents-run-as-nalum-on-polaris.md):
# nalum's own Limi profile, mux and git identity. Nalum clones its checkouts
# itself once its key is on GitHub. limi-hub lets in
# every process of one of fernando's tailnet machines with no token, so
# nftables keeps nalum off the hub's port, and nalum reaches only some of
# the hub's ops, through nalum@<hub>. The hub's host lists this one in
# `relayFrom`, which lets this host's nalum key in for that relay alone.
{
  mkSystemModule,
  lib,
  pkgs,
  inputs,
  fleetPeers,
  ...
}:
let
  name = "nalum";
  home = "/home/${name}";
  key = "${home}/.ssh/id_ed25519";
  keyFile = host: ../../keys/nalum-${host}.nix;
  hostKeyFile = host: ../../keys/host-${host}.nix;

  limi = inputs.limi.lib.host;
  profile = "${home}/${limi.profile}";
  # The hub's ops that nalum on another host may ask: agent events
  # (triggers), web search, and artifacts with their canvases.
  relayed = [
    "triggers.*"
    "web.*"
    "artifact.*"
    "canvas.*"
  ];
  # limi-hub's HTTP port (limi's limi-hub module).
  hubPort = 7377;
  # The fleet peer that runs limi-hub, if any.
  hub = lib.findFirst (peer: lib.elem "limi-hub" fleetPeers.${peer}.services) null (
    lib.attrNames fleetPeers
  );
  # The one command a relayed key runs, whatever command it asks: it joins
  # the ssh channel to the hub's socket in ${limi.hubSockets}, narrowed to
  # `relayed` (`limi hub relay`).
  relay = lib.getExe (
    pkgs.writeShellApplication {
      name = "nalum-hub-relay";
      text = ''
        exec ${profile}/bin/limi hub relay ${lib.escapeShellArgs relayed}
      '';
    }
  );

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
    relayFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Fleet peers whose nalum may reach this host's limi-hub sockets for Nalum (keys/nalum-<peer>.nix), with no shell and no forwarding.";
    };
    power = {
      enable = lib.mkEnableOption "passwordless suspend, hibernate, power-off and reboot for group nalum";
      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Users outside group nalum that get the same power actions.";
      };
    };
    agents = {
      enable = lib.mkEnableOption "Nalum's coding agents as nalum, with its own Limi profile, mux and git identity";
      profileFrom = lib.mkOption {
        type = lib.types.str;
        description = "The user whose Limi profile nalum runs: each `limi switch` of that user moves nalum's profile too.";
      };
    };
  };

  config =
    { config, cfg, ... }:
    let
      # A peer's key exists only after that peer's first activation, so a
      # peer listed before its key is committed is skipped with a warning.
      missing = lib.filter (host: !builtins.pathExists (keyFile host)) (cfg.sshFrom ++ cfg.relayFrom);
      keysOf = hosts: lib.concatMap (host: import (keyFile host)) (lib.subtractLists missing hosts);

      fromProfile = "${config.users.users.${cfg.agents.profileFrom}.home}/${limi.profile}";
      # Every dir from nalum's home down to a file at `path` in it.
      dirsTo =
        path:
        let
          parts = lib.splitString "/" (dirOf path);
        in
        lib.genList (i: "${home}/${lib.concatStringsSep "/" (lib.take (i + 1) parts)}") (lib.length parts);
      gitConfig = ".config/git/config";
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = lib.intersectLists cfg.sshFrom cfg.relayFrom == [ ];
            message = "modules.system.nalum: a peer in both sshFrom and relayFrom would get a shell through its relay key.";
          }
        ];

        users = {
          users.${name} = {
            isNormalUser = true;
            group = name;
            inherit home;
            hashedPassword = "!";
            # `restrict` takes away the pty and every forward; the forced
            # command is all a relayed key runs.
            openssh.authorizedKeys.keys =
              keysOf cfg.sshFrom ++ map (k: ''restrict,command="${relay}" ${k}'') (keysOf cfg.relayFrom);
          };
          groups.${name} = { };
        };

        warnings = map (
          host:
          "modules.system.nalum: keys/nalum-${host}.nix is not committed yet, so nalum@${host} cannot log in."
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

      (lib.mkIf cfg.agents.enable {
        assertions = [
          {
            assertion = hub != null;
            message = "modules.system.nalum.agents: no fleet peer runs limi-hub, so nalum's agents have no hub to reach.";
          }
          {
            assertion = config.networking.nftables.enable;
            message = "modules.system.nalum.agents: the rule that keeps nalum off limi-hub's port is an nftables table.";
          }
          {
            # limi-suite's system part: nalum's login shells find the suite
            # in its own profile, and omo's generic binary runs.
            assertion =
              lib.elem "$HOME/${limi.profile}" config.environment.profiles && config.programs.nix-ld.enable;
            message = "modules.system.nalum.agents: a user here must enable limi-suite, which puts each user's Limi profile on PATH and turns on nix-ld.";
          }
        ];

        users.users.${name} = {
          # Its user manager, and so its limi-host and relay sockets, run
          # from boot.
          linger = true;
          packages = [
            pkgs.gh
            pkgs.git
          ];
        };

        # GitHub's published host key, so nalum's first clone trusts no
        # answer it has not seen before. The hub's, under the names the
        # relay reaches it by (modules/cli/ssh.nix swaps in <hub>.local on
        # the LAN), so the relay never meets an unknown host.
        programs.ssh.knownHosts = {
          "github.com".publicKey =
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        }
        // lib.optionalAttrs (hub != null && builtins.pathExists (hostKeyFile hub)) {
          ${hub} = {
            hostNames = [
              hub
              "${hub}.local"
            ];
            publicKey = import (hostKeyFile hub);
          };
        };
        warnings =
          lib.optional (hub != null && !builtins.pathExists (hostKeyFile hub))
            "modules.system.nalum.agents: keys/host-${hub}.nix is not committed, so nalum's relay to ${hub} trusts no host key.";

        # limi-host holds logind's sleep lock while an agent works
        # (systemd-inhibit --what=sleep). nalum's runs from linger, in no
        # session, so logind asks polkit. Inhibitors only: no
        # *-ignore-inhibit action.
        security.polkit = {
          enable = true;
          extraConfig = ''
            polkit.addRule(function (action, subject) {
              var actions = ["org.freedesktop.login1.inhibit-block-sleep", "org.freedesktop.login1.inhibit-block-idle"];
              if (actions.indexOf(action.id) >= 0 && subject.isInGroup("${name}")) {
                return polkit.Result.YES;
              }
            });
          '';
        };

        # The uid nalum never reaches limi-hub's port, whose tailnet trust
        # would answer it as fernando. Its relay goes over ssh instead.
        networking.nftables = {
          tables.nalum-hub = {
            family = "inet";
            content = ''
              chain output {
                type filter hook output priority filter; policy accept;
                meta skuid "${name}" oifname "tailscale0" tcp dport ${toString hubPort} reject with tcp reset
              }
            '';
          };
          # The ruleset check runs in a sandbox that has no user nalum.
          preCheckRuleset = ''
            sed 's/skuid "${name}"/skuid "nobody"/g' -i ruleset.conf
          '';
        };

        systemd = {
          tmpfiles.rules =
            map (d: "d ${d} 0700 ${name} ${name} -") (lib.unique (dirsTo limi.profile ++ dirsTo gitConfig))
            ++ [
              "d ${home}/${limi.nalumHome} 0700 ${name} ${name} -"
              # Nalum is nalum's only omo, so omo's home is Nalum's.
              "L ${home}/.omo - - - - ${limi.nalumHome}"
              "L+ ${home}/${gitConfig} - - - - ${profile}/${limi.nalumGitConfig}"
            ];

          # fernando's home stays closed to nalum, so nalum's profile is a
          # profile of its own, set to the build that fernando's holds.
          services.nalum-limi-profile = {
            description = "nalum runs ${cfg.agents.profileFrom}'s Limi build";
            wantedBy = [ "multi-user.target" ];
            after = [ "systemd-tmpfiles-setup.service" ];
            path = [
              config.nix.package
              pkgs.coreutils
              pkgs.util-linux
              config.systemd.package
            ];
            serviceConfig.Type = "oneshot";
            script = ''
              src=$(readlink -f ${fromProfile} || true)
              if [ -z "$src" ] || [ ! -e "$src" ]; then
                echo "${fromProfile} holds no Limi build yet"
                exit 0
              fi
              if [ "$(readlink -f ${profile} || true)" = "$src" ]; then
                exit 0
              fi
              runuser -u ${name} -- env HOME=${home} nix-env --profile ${profile} --set "$src"
              runuser -u ${name} -- env HOME=${home} nix-env --profile ${profile} --delete-generations old
              # As `limi switch` restarts fernando's: its panes outlive it. A
              # new build gets a fresh start past the start limit.
              systemctl --user -M ${name}@ reset-failed limi-host.service || true
              systemctl --user -M ${name}@ restart limi-host.service ||
                echo "nalum's user manager is not up; its limi-host starts on the new build"
            '';
          };
          paths.nalum-limi-profile = {
            wantedBy = [ "multi-user.target" ];
            pathConfig.PathChanged = dirOf fromProfile;
          };

          # A running game takes the CPU from the agents
          # (modules/games/steam.nix): their slice gets only what it leaves.
          services.game-priority = lib.mkIf config.programs.gamemode.enable {
            script = "systemctl set-property --runtime user-$(id -u ${name}).slice CPUWeight=idle";
            preStop = "systemctl set-property --runtime user-$(id -u ${name}).slice CPUWeight=";
          };

          user = {
            # nalum's main mux, as limi-suite's server part runs fernando's;
            # his own unit of this name, from Home Manager, overrides this one.
            services = {
              limi-host = {
                description = "limi-host keep: nalum's mux and coding agents";
                wantedBy = [ "default.target" ];
                unitConfig = {
                  ConditionUser = name;
                  ConditionPathExists = "${profile}/${limi.path}/limi-host";
                  # A build that exits at once fails the unit after five
                  # tries instead of restarting forever: the default limit
                  # (5 in 10s) never trips at one start per 4s.
                  StartLimitIntervalSec = 120;
                  StartLimitBurst = 5;
                };
                environment = {
                  PATH = lib.mkForce "${profile}/${limi.path}:${profile}/bin:/etc/profiles/per-user/${name}/bin:/run/current-system/sw/bin";
                  # The machine's own work (the HTTP port, the copies, the
                  # hub link) is fernando's mux's.
                  LIMI_SIDE_MUX = "1";
                }
                // {
                  LIMI_HUB_SOCKET = "%t/limi-hub/server.sock";
                };
                serviceConfig = {
                  ExecStart = "${profile}/${limi.path}/limi-host keep";
                  # Only the server stops: its panes' zmx sessions must
                  # outlive a restart.
                  KillMode = "process";
                  Restart = "always";
                  RestartSec = 2;
                };
              };
            }
            // {
              "nalum-hub@" = {
                description = "A connection to limi-hub's socket on ${toString hub}";
                unitConfig.ConditionUser = name;
                serviceConfig = {
                  ExecStart = "${config.programs.ssh.package}/bin/ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes ${name}@${toString hub} hub";
                  StandardInput = "socket";
                  StandardOutput = "socket";
                  StandardError = "journal";
                };
              };
            };

            sockets.nalum-hub = {
              description = "limi-hub's socket on ${toString hub}, for nalum";
              wantedBy = [ "sockets.target" ];
              unitConfig.ConditionUser = name;
              socketConfig = {
                ListenStream = "%t/limi-hub/server.sock";
                Accept = true;
                SocketMode = "0600";
                DirectoryMode = "0700";
              };
            };
          };
        };
      })
    ];
}
