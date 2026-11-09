# realdu: what each entry of a directory really takes on disk.
#
# du counts every APFS clone and btrfs reflink at full size, so a folder of
# pnpm or uv installs can look many times bigger than the space deleting it
# frees. `realdu [DIR]` lists each entry with du's size next to its unique
# size, the blocks nothing else shares:
#   darwin: realdu-apfs.c sums APFS's per-file private size; no common tool
#           reads it (du, ncdu and dust all count clones in full).
#   linux:  btrfs's exclusive size from `btrfs filesystem du`; on any other
#           filesystem, du with each hard-linked file counted once.
#
# Unique is a lower bound: blocks shared only between two entries count for
# neither, though deleting both frees them. On btrfs, blocks a snapshot still
# holds count as shared, so they free only once the snapshot expires.
{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  realdu-apfs = pkgs.runCommandCC "realdu-apfs" { } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -Wextra -Werror -o $out/bin/realdu-apfs ${./realdu-apfs.c}
  '';
  realdu = pkgs.writeShellApplication {
    name = "realdu";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin realdu-apfs
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.btrfs-progs;
    text = builtins.readFile ./realdu.sh;
  };
in
mkUserModule {
  name = "realdu";
  home.home.packages = [ realdu ];
}
