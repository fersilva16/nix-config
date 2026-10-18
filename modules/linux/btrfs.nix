# btrfs upkeep: scrub and @home snapshots, for any host whose disks are btrfs.
#
# Every part is gated on the evaluated fileSystems, so a host without btrfs
# gets nothing and a host's disk file never has to know this module exists.
#
# Scrub: re-reads every block and checks it against its checksum, so silent
# corruption is found while a good copy (a snapshot or the backup) still
# exists. Monthly is upstream's default and plenty for one NVMe. autoScrub
# lists each btrfs device once, so the three subvolumes cost one scrub.
#
# Snapshots: snapper over btrbk. Snapper does what local history needs:
# hourly timeline snapshots with tiered cleanup, and `snapper -c home diff`
# / `undochange` to restore a file without digging through snapshot dirs.
# ALLOW_GROUPS lets wheel users do that without sudo. btrbk's strength is
# send/receive to another btrfs disk, which is backup, not local history.
# Snapshots live on the same disk, so they cover "I deleted or overwrote it",
# not a dead disk.
{ mkSystemModule, lib, ... }:
mkSystemModule {
  name = "btrfs";
  config =
    { config, ... }:
    let
      isBtrfs = mount: (config.fileSystems.${mount}.fsType or null) == "btrfs";
    in
    {
      services.btrfs.autoScrub.enable = lib.any (fs: fs.fsType == "btrfs") (
        lib.attrValues config.fileSystems
      );

      services.snapper.configs.home = lib.mkIf (isBtrfs "/home") {
        SUBVOLUME = "/home";
        ALLOW_GROUPS = [ "wheel" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        # A day of hours, a week of days, a month of weeks, a quarter of
        # months. Short monthly tail on purpose: a snapshot pins every block
        # changed since, and /home holds big churning data (game libraries).
        TIMELINE_LIMIT_HOURLY = 24;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 3;
        TIMELINE_LIMIT_QUARTERLY = 0;
        TIMELINE_LIMIT_YEARLY = 0;
      };

      # snapper needs <subvolume>/.snapshots to exist as a subvolume and does
      # not create it. tmpfiles `v` creates a subvolume on btrfs (a plain dir
      # elsewhere) and leaves an existing one alone, so a fresh install needs
      # no manual `snapper create-config`.
      systemd.tmpfiles.rules = lib.mkIf (isBtrfs "/home") [ "v /home/.snapshots 0750 root wheel -" ];
    };
}
