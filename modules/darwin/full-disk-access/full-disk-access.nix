# Full Disk Access for the Nix daemon and its maintenance jobs.
#
# macOS ties a privacy grant to a binary's path and signature, and every Nix
# upgrade moves nix-daemon to a new store path, so a grant given to it stops
# applying without a word. Without the grant, garbage collection aborts on the
# first app bundle macOS has stamped as launched (com.apple.macl) and frees
# nothing.
#
# The daemon and the gc/optimise jobs start through fda-exec instead: a small
# launcher at a fixed root-owned path, re-signed with a name-based identity on
# every activation (the lan-mouse trick). It stays the parent of what it
# starts, and a child inherits its parent's grant, so one grant for
# /usr/local/libexec/fda-exec covers every Nix version.
{
  mkSystemModule,
  pkgs,
  lib,
  ...
}:
let
  path = "/usr/local/libexec/fda-exec";
  signingId = "org.nix-config.fda-exec";
  fda-exec = pkgs.runCommandCC "fda-exec" { } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -Wextra -Werror -o $out/bin/fda-exec ${./fda-exec.c}
  '';
  via = command: lib.mkForce "${path} ${command}";
in
mkSystemModule {
  name = "full-disk-access";
  config =
    { config, ... }:
    let
      nix = config.nix.package;
    in
    {
      # preActivation: the launchd step that restarts nix-daemon on its new
      # command runs before postActivation, so the launcher must exist first.
      system.activationScripts.preActivation.text = ''
        install -d /usr/local/libexec
        install -m 755 ${fda-exec}/bin/fda-exec ${path}.new
        /usr/bin/codesign --force --sign - --identifier ${signingId} \
          -r='designated => identifier "${signingId}"' ${path}.new
        mv -f ${path}.new ${path}
      '';

      launchd.daemons = {
        # A socket-activated daemon must call launch_activate_socket itself,
        # which a child of the launcher cannot do.
        nix-daemon.command = lib.mkIf (!config.services.nix-daemon.enableSocketListener) (
          via (lib.getExe' nix "nix-daemon")
        );
        nix-gc.command = lib.mkIf config.nix.gc.automatic (
          via "${nix}/bin/nix-collect-garbage ${config.nix.gc.options}"
        );
        nix-optimise.command = lib.mkIf config.nix.optimise.automatic (
          via "${lib.getExe' nix "nix-store"} --optimise"
        );
      };
    };
}
