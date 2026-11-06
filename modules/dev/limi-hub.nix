# limi-hub (inputs.limi): Limi's always-on daemon, for altair. It serves the
# other machines' limi-host (limi-suite/server.nix) over the tailnet. Its
# one-time setup is manual and lives in Limi.
#
# The hub runs from the user's Limi profile, not from the pinned input, so
# `limi switch --host altair` moves it to a new build and restarts it without
# a rebuild here. The pin only seeds an empty profile.
{
  mkUserModule,
  forPlatform,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  limi = inputs.limi.packages.${pkgs.stdenv.hostPlatform.system};
  inherit (inputs.limi.lib) host;
  port = 7377;
  # Every directory from $HOME down to the profile, which limi-hub must be
  # able to search to reach its binary.
  profileDirs =
    let
      parts = lib.splitString "/" (dirOf host.profile);
    in
    lib.genList (i: "$HOME/${lib.concatStringsSep "/" (lib.take (i + 1) parts)}") (lib.length parts);
in
mkUserModule {
  name = "limi-hub";
  # The hub's clients reach it over the tailnet only.
  requires = [ "tailscale" ];
  system =
    { enabledUsers }:
    let
      user = lib.head (lib.attrNames enabledUsers);
      home = "/home/${user}";
    in
    {
      # limi-suite's limi-host finds the hub here (fleetPeers).
      fleet.services = [ "limi-hub" ];
    }
    // forPlatform {
      linux = {
        # The personal Nalum's sessions run omo's generic glibc binary, as
        # limi-suite's do; nix-ld serves its loader path.
        programs.nix-ld.enable = true;

        # The hub starts Nalum's sessions in a login shell as the user, which
        # finds `nalum` in the profile. Last, so it never shadows /run/wrappers
        # or the system profiles.
        environment.profiles = lib.mkAfter [ "$HOME/${host.profile}" ];

        assertions = [
          {
            assertion = lib.length (lib.attrNames enabledUsers) == 1;
            message = "limi-hub serves one user; enable it for exactly one.";
          }
        ];

        users = {
          users = {
            limi-hub = {
              isSystemUser = true;
              group = "limi-hub";
              extraGroups = [ "nalum" ];
              home = "/var/lib/limi-hub";
              createHome = true;
              homeMode = "700";
            };
            ${user}.homeMode = "711";
          };
          groups = {
            limi-hub = { };
            nalum.members = [
              user
              "limi-hub"
            ];
          };
        };

        security.sudo.extraRules = [
          {
            users = [ "limi-hub" ];
            runAs = user;
            commands = [
              {
                command = "ALL";
                options = [
                  "NOPASSWD"
                  "SETENV"
                ];
              }
            ];
          }
        ];

        systemd = {
          # The hub makes its own runtime dirs and links.
          tmpfiles.rules = [
            # The raisers' socket for needs-you items (needs-you.sock); group nalum may raise.
            "d /run/limi-hub 0750 limi-hub nalum -"
          ];

          services.limi-hub = {
            wantedBy = [ "multi-user.target" ];
            # Home Manager seeds the profile; on a first boot the hub waits for it.
            after = [
              "network-online.target"
              "tailscaled.service"
              "home-manager-${user}.service"
            ];
            wants = [
              "network-online.target"
              "home-manager-${user}.service"
            ];
            # `limi switch --host` asks the hub to exit and restarts it from the
            # profile; never give up on it.
            unitConfig.StartLimitIntervalSec = 0;
            path = [ "/run/wrappers" ];
            environment = {
              LIMI_NALUM_PROJECTS = "${home}/nalum";
              OMO_CODING_AGENT_DIR = "${home}/nalum/.agent";
            };
            serviceConfig = {
              User = "limi-hub";
              Group = "limi-hub";
              ExecStart = "${home}/${host.profile}/${host.hub}";
              Restart = "always";
              RestartSec = 2;
              UMask = "0077";
              # The personal Nalum's sessions outlive a hub restart; limi-hub reattaches to them.
              KillMode = "process";
            };
          };
        };

        # Tailnet only: never on the LAN interface.
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
      };
    };
  home.home = forPlatform {
    linux = {
      packages = [ pkgs.tmux ];
      # Seeds an empty profile with the pinned hub suite; `limi switch --host`
      # owns it after that. `limi pin` runs nix-env from PATH, so hand it this
      # host's nix. limi-hub reaches its binary through these dirs, and a
      # shell may have made ~/.local 0700.
      activation.limiHubProfile = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          run mkdir -p "${lib.last profileDirs}"
          run chmod o+x ${lib.concatStringsSep " " (map (d: ''"${d}"'') profileDirs)}
          run env PATH="${pkgs.nix}/bin:$PATH" ${limi.limi-hub-suite}/bin/limi pin ${limi.limi-hub-suite}
        '';
      };
    };
  };
}
