# btrfs upkeep: scrub, for any host whose disks are btrfs.
#
# Gated on the evaluated fileSystems, so a host without btrfs gets nothing and
# a host's disk file never has to know this module exists.
#
# Scrub: re-reads every block and checks it against its checksum, so silent
# corruption is found while a good copy (the backup) still exists. Monthly is
# upstream's default and plenty for one NVMe. autoScrub lists each btrfs
# device once, so the subvolumes cost one scrub.
#
# No local snapshots: hourly snapshots of @home pinned every block that git
# worktrees and their builds rewrote, so deleting a build freed nothing for
# months. Off-box copies are modules/linux/backup.nix's job.
{ mkSystemModule, lib, ... }:
mkSystemModule {
  name = "btrfs";
  config =
    { config, ... }:
    {
      services.btrfs.autoScrub.enable = lib.any (fs: fs.fsType == "btrfs") (
        lib.attrValues config.fileSystems
      );
    };
}
