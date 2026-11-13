# backup — encrypted, compressed, deduplicated off-box copies with restic.
#
# A source host (`to = "<peer>"`) backs up its btrfs subvolumes once a day
# to a fleet peer that keeps a store (`store = "<dir>"`), over SFTP. The
# repository is restic's v2 format: every pack is encrypted and compressed,
# so the store only ever holds ciphertext. The password lives in 1Password
# (op://Nix/<Host> Restic/password) and each run reads it with `op read`
# through the Nix vault's read-only service account, the one opnix uses
# (modules/system/nix.nix), so it is on neither disk, and
# 1Password is how it is recovered when the source is gone. The same
# repository format takes an S3, B2 or rclone backend, so a cloud copy is one
# more services.restic.backups entry with the same password.
#
# restic reads read-only snapshots, not the live tree, so a file that
# changes during the run is never half old and half new. Each snapshot is
# bind-mounted over its own subvolume inside the backup's mount namespace:
# the repository records /home, not /home/.backup-snapshot, and a restore
# lands on the same paths. A snapshot stops at a nested subvolume (~/.cache,
# snapper's .snapshots, the hub's mirror), so those come out empty.
#
# The source wakes the peer first (`wake`, modules/networking/wake-on-lan.nix)
# and waits for its SFTP: a desktop store may be asleep, the source never is,
# and Persistent=true runs a missed day at the next boot.
#
# The store side is one SFTP-only user that owns the store (0700), with one
# repository dir per source host, which the source's `restic init` makes.
# No chroot: sshd wants every dir above a chroot owned by root, and /data on
# polaris is fernando's. The user can still only speak SFTP, and every file
# it writes is ciphertext. The store advertises its path to the fleet, so a
# source never repeats it.
{
  mkSystemModule,
  fleetPeers,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  host = inputs.limi.lib.host;
  storeUser = "backup";
  state = "/var/lib/restic-backup";
  key = "${state}/ssh_id_ed25519";
  # Relative to each subvolume: btrfs snapshots stay on the subvolume's own
  # filesystem, and a nested subvolume never shows up in the parent's own
  # snapshots.
  snapshot = ".backup-snapshot";
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";

  # Rebuildable or huge: caches, agent runtimes, package stores, build dirs.
  # `--exclude-caches` also skips every dir with a CACHEDIR.TAG (cargo's
  # target/).
  defaultExclude = [
    "/home/*/.cache"
    "/home/*/.omo/binary-runtime"
    "/home/*/.nalum/binary-runtime"
    "/home/*/.local/share/Trash"
    "/home/*/.local/share/pnpm"
    "/home/*/.npm"
    "/home/*/.cargo/registry"
    "/home/*/.cargo/git"
    "/home/*/.rustup"
    "node_modules"
    ".direnv"
  ];
in
mkSystemModule {
  name = "backup";

  extraOptions = {
    to = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Fleet peer that stores this host's backup; null backs nothing up.";
    };
    subvolumes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Btrfs subvolumes to back up besides /home, each from a read-only snapshot.";
    };
    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "restic exclude patterns on top of the module's own.";
    };
    notify = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User whose `limi notify` hears when the last good backup is older than 3 days.";
    };
    store = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Directory where this host keeps its peers' repositories; null stores none.";
    };
  };

  config =
    { config, cfg, ... }:
    let
      inherit (config.networking) hostName;
      subvolumes = [ "/home" ] ++ cfg.subvolumes;
      ssh = config.programs.ssh.package;
      target = "${storeUser}@${cfg.to}";
      # HostKeyAlias: the peer's key is pinned under its name, whether ssh
      # reaches it on the LAN or the tailnet (modules/cli/ssh.nix).
      sshArgs = lib.concatStringsSep " " [
        "-i ${key}"
        "-o IdentitiesOnly=yes"
        "-o BatchMode=yes"
        "-o HostKeyAlias=${cfg.to}"
        "-o UserKnownHostsFile=${state}/known_hosts"
        "-o StrictHostKeyChecking=accept-new"
      ];
      # Quoted as one whole word, the way both systemd's ExecStart and the
      # shell take it.
      sftpOption = "'sftp.command=${ssh}/bin/ssh ${sshArgs} ${target} -s sftp'";
      restic = "${lib.getExe pkgs.restic} -o ${sftpOption}";
      unit = "restic-backups-${cfg.to}";
      # altair's item is "Altair Restic".
      item = "${lib.toUpper (lib.substring 0 1 hostName)}${lib.substring 1 (-1) hostName} Restic";

      password = pkgs.writeShellScript "restic-password" ''
        OP_SERVICE_ACCOUNT_TOKEN=$(< ${lib.escapeShellArg config.services.onepassword-secrets.tokenFile})
        export OP_SERVICE_ACCOUNT_TOKEN
        exec ${lib.getExe pkgs._1password-cli} read --no-newline "op://Nix/${item}/password"
      '';

      reach = pkgs.writeShellScript "restic-reach" ''
        ${lib.optionalString (
          fleetPeers.${cfg.to} ? wakeOnLan
        ) "${lib.getExe config.modules.system.wake-on-lan.package} ${cfg.to}"}
        deadline=$((SECONDS + 600))
        while ! err=$(echo pwd | ${ssh}/bin/sftp -q ${sshArgs} -b - ${target} 2>&1 >/dev/null); do
          if [ "$SECONDS" -ge "$deadline" ]; then
            echo "${cfg.to} took no SFTP connection for 10 minutes: $err" >&2
            exit 1
          fi
          sleep 10
        done
      '';

      takeSnapshots = pkgs.writeShellScript "backup-snapshots-take" ''
        set -e
        for s in ${lib.escapeShellArgs subvolumes}; do
          if [ -e "$s/${snapshot}" ]; then
            ${btrfs} subvolume delete "$s/${snapshot}"
          fi
          ${btrfs} subvolume snapshot -r "$s" "$s/${snapshot}"
        done
      '';
      dropSnapshots = pkgs.writeShellScript "backup-snapshots-drop" ''
        set -e
        for s in ${lib.escapeShellArgs subvolumes}; do
          if [ -e "$s/${snapshot}" ]; then
            ${btrfs} subvolume delete "$s/${snapshot}"
          fi
        done
      '';

      # The last ExecStart: it runs only when the backup, the unlock and the
      # prune before it all passed. A check reads a tenth of the packs, so a
      # weekly one has read the whole repository in about ten weeks.
      finish = pkgs.writeShellScript "restic-finish" ''
        set -e
        checked=${state}/last-check
        now=$(date +%s)
        if [ ! -e "$checked" ] || [ $((now - $(stat -c %Y "$checked"))) -ge $((7 * 86400)) ]; then
          ${restic} check --read-data-subset=10%
          touch "$checked"
        fi
        touch ${state}/last-success
      '';

      watch = pkgs.writeShellScript "restic-backup-watch" ''
        set -e
        stamp=${state}/last-success
        id=backup-${hostName}
        hint="journalctl -u ${unit} on ${hostName}"
        ${
          if cfg.notify == null then
            "limi() { :; }"
          else
            ''
              limi() {
                ${pkgs.util-linux}/bin/runuser -u ${cfg.notify} -- \
                  ${config.users.users.${cfg.notify}.home}/${host.profile}/bin/limi "$@"
              }
            ''
        }
        if [ -e "$stamp" ]; then
          now=$(date +%s)
          last=$(stat -c %Y "$stamp")
          days=$(((now - last) / 86400))
          if [ "$days" -lt 3 ]; then
            limi notify clear "$id"
            exit 0
          fi
          reason="No backup of ${hostName} has reached ${cfg.to} in $days days: $hint"
        else
          reason="No backup of ${hostName} has reached ${cfg.to} yet: $hint"
        fi
        limi notify raise "$id" "$reason" --source backup --level interrupt
        echo "$reason" >&2
        exit 1
      '';

      stateDir = {
        StateDirectory = "restic-backup";
        # The private key is 0600 on its own; the public one is for reading.
        StateDirectoryMode = "0755";
      };
    in
    lib.mkMerge [
      (lib.mkIf (cfg.to != null) {
        services.restic.backups.${cfg.to} = {
          repository = "sftp:${target}:${fleetPeers.${cfg.to}.backupStore}/${hostName}-restic";
          environmentFile = "${pkgs.writeText "restic-env" "RESTIC_PASSWORD_COMMAND=${password}\n"}";
          extraOptions = [ sftpOption ];
          initialize = true;
          paths = subvolumes;
          exclude = defaultExclude ++ cfg.exclude;
          extraBackupArgs = [ "--exclude-caches" ];
          pruneOpts = [
            "--keep-daily 14"
            "--keep-weekly 8"
            "--keep-monthly 12"
          ];
          backupPrepareCommand = "${reach}";
        };

        systemd = {
          services = {
            ${unit} = {
              requires = [
                "restic-backup-key.service"
                "restic-backup-snapshots.service"
              ];
              after = [
                "restic-backup-key.service"
                "restic-backup-snapshots.service"
              ];
              onSuccess = [ "restic-backup-watch.service" ];
              onFailure = [ "restic-backup-watch.service" ];
              serviceConfig = stateDir // {
                BindReadOnlyPaths = map (s: "${s}/${snapshot}:${s}") subvolumes;
                ExecStart = lib.mkAfter [ "${finish}" ];
              };
            };

            # Generated where it is used, so the private key never leaves
            # this host; the store accepts its public half (keys/backup.nix).
            restic-backup-key = {
              description = "SSH key the restic backup reaches ${cfg.to} with";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = stateDir // {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                if [ ! -e ${key} ]; then
                  ${ssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "restic@${hostName}" -f ${key}
                fi
              '';
            };

            # Up only while the backup that requires it runs: once that ends,
            # nothing needs it, and stopping it deletes the snapshots.
            restic-backup-snapshots = {
              description = "Read-only snapshots the restic backup reads";
              restartIfChanged = false;
              unitConfig.StopWhenUnneeded = true;
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${takeSnapshots}";
                ExecStop = "${dropSnapshots}";
              };
            };

            # Runs after every backup and daily on its own, so a backup that
            # hangs or never starts is still noticed. Raising an id that is up
            # changes nothing; a failed unit is the second signal.
            restic-backup-watch = {
              description = "Notice when ${hostName}'s backup goes stale";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${watch}";
              };
            };
          };

          timers.restic-backup-watch = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "daily";
              Persistent = true;
            };
          };
        };
      })

      (lib.mkIf (cfg.store != null) {
        fleet.backupStore = cfg.store;

        users = {
          users.${storeUser} = {
            isSystemUser = true;
            group = storeUser;
            home = "/var/empty";
            openssh.authorizedKeys.keys = map (k: "restrict ${k}") (import ../../keys/backup.nix);
          };
          groups.${storeUser} = { };
        };

        # Last in sshd_config: a Match block runs to the end of the file.
        services.openssh.extraConfig = lib.mkAfter ''
          Match User ${storeUser}
            ForceCommand internal-sftp -u 0077 -d ${cfg.store}
            AllowTcpForwarding no
            AllowAgentForwarding no
            X11Forwarding no
            PermitTTY no
        '';

        # Not tmpfiles: the store may sit on a nofail mount, and a dir made
        # before it mounts would land on the root disk. Without the mount
        # this fails, the store is missing, and the sources' runs fail.
        systemd.services.backup-store = {
          description = "Backup store on ${cfg.store}";
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = cfg.store;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "install -d -m 0700 -o ${storeUser} -g ${storeUser} ${cfg.store}";
        };
      })
    ];
}
