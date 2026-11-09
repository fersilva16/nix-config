# Full Disk Access for Nix's scheduled garbage collection and store optimise.
#
# macOS stamps an app bundle it has launched (com.apple.macl), and only a
# process with Full Disk Access may then delete or relink it. Without the
# grant, nix-collect-garbage aborts on the first stamped bundle in the store
# and frees nothing. A grant follows a binary's path and signature, and every
# Nix upgrade moves the Nix binaries, so the grant goes to nix-fda: a launcher
# at a fixed root-only path, re-signed on every activation with a name-based
# identity (the lan-mouse trick). It stays the parent of the Nix command it
# starts, and the command works under its grant.
#
# The grant must not reach anything but these two jobs. nix-fda runs only the
# commands compiled into it, only as root, with a fixed environment, and the
# hardened runtime keeps DYLD_* variables from loading code into it.
# nix-daemon gets no grant: it runs every user's build code, which would
# inherit it. A collection through the daemon still stops at a stamped bundle;
# `sudo launchctl kickstart system/org.nixos.nix-gc` runs the scheduled one now.
{
  mkSystemModule,
  pkgs,
  lib,
  ...
}:
let
  path = "/usr/local/libexec/nix-fda";
  signingId = "org.nix-config.nix-fda";
  cArgv = args: "{ ${lib.concatMapStringsSep ", " builtins.toJSON args}, NULL }";
in
mkSystemModule {
  name = "nix-full-disk-access";
  config =
    { config, ... }:
    let
      nix = config.nix.package;
      gcArgv = [
        "${nix}/bin/nix-collect-garbage"
      ]
      ++ lib.filter (arg: arg != "") (lib.splitString " " config.nix.gc.options);
      optimiseArgv = [
        (lib.getExe' nix "nix-store")
        "--optimise"
      ];
      commands = pkgs.writeText "nix-fda-commands.h" ''
        static char *const gc_argv[] = ${cArgv gcArgv};
        static char *const optimise_argv[] = ${cArgv optimiseArgv};
      '';
      nix-fda = pkgs.runCommandCC "nix-fda" { } ''
        mkdir -p $out/bin
        cp ${commands} nix-fda-commands.h
        $CC -O2 -Wall -Wextra -Werror -I. -o $out/bin/nix-fda ${./nix-fda.c}
      '';
    in
    {
      # fda-exec ran any program it was given under the grant; it must not
      # survive on a machine that once installed it.
      system.activationScripts.postActivation.text = ''
        rm -f /usr/local/libexec/fda-exec
        install -d /usr/local/libexec
        install -m 700 ${nix-fda}/bin/nix-fda ${path}.new
        /usr/bin/codesign --force --sign - --options runtime --identifier ${signingId} \
          -r='designated => identifier "${signingId}"' ${path}.new
        mv -f ${path}.new ${path}
      '';

      launchd.daemons = {
        nix-gc.command = lib.mkIf config.nix.gc.automatic (lib.mkForce "${path} gc");
        nix-optimise.command = lib.mkIf config.nix.optimise.automatic (lib.mkForce "${path} optimise");
      };
    };
}
