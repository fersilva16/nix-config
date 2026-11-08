# limi-hub: Limi's always-on daemon, for altair. It serves the other
# machines' limi-host (limi-suite/server.nix) over the tailnet. Its one-time
# setup is manual and lives in Limi.
#
# The hub runs from the user's Limi profile, which `limi switch --host altair`
# fills from polaris and moves to each new build, restarting the hub. Nothing
# here builds Limi.
{
  mkUserModule,
  forPlatform,
  config,
  pkgs,
  lib,
  ...
}:
let
  host = import ../../lib/limiHost.nix;
  port = 7377;
  # Every directory from $HOME down to the profile, which limi-hub must be
  # able to search to reach its binary.
  profileDirs =
    let
      parts = lib.splitString "/" (dirOf host.profile);
    in
    lib.genList (i: "$HOME/${lib.concatStringsSep "/" (lib.take (i + 1) parts)}") (lib.length parts);
  hubHome = "/var/lib/limi-hub";
  rootIsBtrfs = (config.fileSystems."/".fsType or null) == "btrfs";
  # limi-hub's server dir, relative to its home, and the mirror its
  # connectors write in it as plain text for group nalum to read.
  hubDir = ".local/state/limi/hub";
  mirror = "${hubHome}/${hubDir}/mirror";
  # Every directory from the hub's home down to the mirror, which group
  # nalum must be able to search.
  mirrorParents =
    let
      parts = lib.splitString "/" hubDir;
    in
    [ hubHome ]
    ++ lib.genList (i: "${hubHome}/${lib.concatStringsSep "/" (lib.take (i + 1) parts)}") (
      lib.length parts
    );
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
      # The 1Password service account token: the user's file, mode 640 with
      # group limi-hub, so the hub reads it and he rotates it.
      opToken = "${home}/.local/state/limi/op-token";
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
              home = hubHome;
              # tmpfiles makes the home, as a btrfs subvolume: the users
              # module would make a plain dir first, on every fresh install.
              createHome = false;
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
          #
          # The hub's home is its own subvolume, so snapper keeps its history
          # and a backup snapshots it alone. `v` makes one on btrfs (a plain
          # dir elsewhere) and leaves an existing dir alone, so converting a
          # live home is a one-time move by hand. The mirror is a subvolume
          # too: connectors rewrite it constantly and rebuild it from their
          # sources, and a snapshot stops at a nested subvolume.
          tmpfiles.rules = [
            # The raisers' socket for needs-you items (needs-you.sock); group nalum may raise.
            "d /run/limi-hub 0750 limi-hub nalum -"
            # The hub resumes a personal Nalum session only if it can read its
            # transcript, so the sessions dir and the dirs above it are group
            # nalum, setgid so new files and subdirs inherit the group.
            # Declaring the parents keeps tmpfiles from making them root's.
            "d ${home}/nalum 2770 ${user} nalum -"
            "d ${home}/nalum/.agent 2770 ${user} nalum -"
            "d ${home}/nalum/.agent/sessions 2770 ${user} nalum -"
            # nalum's gid is allocated per machine, so files restored from
            # another one may carry a stale group. Group only: their modes stay.
            "Z ${home}/nalum/.agent/sessions - - nalum -"
          ]
          # Group nalum reads the mirror and nothing else of the hub's home:
          # search only on each dir above it, read on it, and a default entry
          # that what the hub writes later inherits. The mirror chmods every
          # dir and file it writes, which clears a setgid bit, so the group
          # comes from ACLs. A chmod sets an ACL's mask, so these dirs keep
          # group search (0710) for the mask to let nalum's entry through.
          ++ lib.concatMap (d: [
            "${if d == hubHome then "v" else "d"} ${d} 0710 limi-hub limi-hub -"
            "a+ ${d} - - - - group:nalum:--x"
          ]) mirrorParents
          ++ [
            "v ${mirror} 0750 limi-hub limi-hub -"
            "A+ ${mirror} - - - - group:nalum:r-X,default:group:nalum:r-X"
          ]
          # snapper needs the .snapshots subvolume and does not make it.
          ++ lib.optional rootIsBtrfs "v ${hubHome}/.snapshots 0750 root wheel -";

          services.limi-hub = {
            wantedBy = [ "multi-user.target" ];
            # Home Manager makes the profile's dirs searchable first. Until
            # `limi switch --host` fills the profile, the hub restarts below.
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
            # profile, which may still be empty; never give up on it.
            unitConfig.StartLimitIntervalSec = 0;
            path = [ "/run/wrappers" ];
            environment = {
              LIMI_NALUM_PROJECTS = "${home}/nalum";
              OMO_CODING_AGENT_DIR = "${home}/nalum/.agent";
              LIMI_OP_TOKEN = opToken;
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

        # Hourly local history of the hub's state, like /home's in
        # modules/linux/btrfs.nix but without the monthly tail: the off-box
        # backup keeps the long history.
        services.snapper.configs.limi-hub = lib.mkIf rootIsBtrfs {
          SUBVOLUME = hubHome;
          ALLOW_GROUPS = [ "wheel" ];
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
          TIMELINE_LIMIT_HOURLY = 24;
          TIMELINE_LIMIT_DAILY = 7;
          TIMELINE_LIMIT_WEEKLY = 4;
          TIMELINE_LIMIT_MONTHLY = 0;
          TIMELINE_LIMIT_QUARTERLY = 0;
          TIMELINE_LIMIT_YEARLY = 0;
        };

        # The hub's state exists nowhere else, so a host that backs up
        # (modules/linux/backup.nix) takes it too. The hub's service account
        # reads the repository password, and the hub's user hears when the
        # backup goes stale.
        modules.system.backup = {
          subvolumes = [ hubHome ];
          exclude = [ mirror ];
          opTokenFile = lib.mkDefault opToken;
          notify = lib.mkDefault user;
        };
      };
    };
  home.home = forPlatform {
    linux = {
      packages = [ pkgs.tmux ];
      # limi-hub reaches its binary through these dirs, and a shell may have
      # made ~/.local 0700. `limi switch --host` fills the profile; until it
      # does, say how.
      activation.limiHubProfile = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          run mkdir -p "${lib.last profileDirs}"
          run chmod o+x ${lib.concatStringsSep " " (map (d: ''"${d}"'') profileDirs)}
          if [ ! -x "$HOME/${host.profile}/${host.hub}" ]; then
            warnEcho "No limi-hub in ~/${host.profile}: the hub waits for it."
            warnEcho "Fill it from polaris with 'limi switch --host ${config.networking.hostName}'."
          fi
        '';
      };
    };
  };
}
