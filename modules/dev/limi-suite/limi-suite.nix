# Limi (inputs.limi): everything it ships, as one package (limi-suite). Limi
# owns its tools, its `limi` CLI and the paths a host wires (`lib.host`); this
# module is only the host glue.
#
# The suite lives in its own Nix profile, not in the Home Manager build, so a
# Limi change never touches nix-config: `limi switch` builds ~/limi into it,
# `limi switch --pinned` goes back to the version flake.lock pins. Each
# activation hands that pin to `limi pin`, which follows it unless a
# `limi switch` build is active.
#
# Can't be enabled together with `omo` (asserted below): Limi's Nalum is omo,
# and both install `omo` and write the same ~/.omo files.
{
  mkUserModule,
  forPlatform,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  pinned = inputs.limi.packages.${pkgs.stdenv.hostPlatform.system}.limi-suite;
  inherit (inputs.limi.lib) host;
  homeOf =
    username:
    forPlatform {
      darwin = "/Users/${username}";
      linux = "/home/${username}";
    };
in
mkUserModule {
  name = "limi-suite";
  requires = [ "omo-home" ];
  parts = {
    gateway = import ./gateway.nix {
      inherit
        pkgs
        host
        homeOf
        forPlatform
        ;
    };
  };
  # Nalum's linux binary is generic glibc (/lib64/ld-linux-x86-64.so.2), and so
  # are the native modules and senpi-desktop-engine it unpacks into
  # ~/.omo/binary-runtime at run time, where patchelf can't reach them.
  # nix-ld serves that loader path, so all of them run unpatched.
  #
  # The profile also joins NixOS's profile list, so the whole graphical
  # session (Noctalia's launcher included) gets its share/ on XDG_DATA_DIRS
  # (desktop entries such as limi-desktop) and its bin/ on PATH. A new
  # entry shows up after the next login.
  system = forPlatform {
    linux = {
      programs.nix-ld.enable = true;
      # Last, so it never shadows /run/wrappers or the system profiles.
      environment.profiles = lib.mkAfter [ "$HOME/${host.profile}" ];
    };
  };
  home =
    { username, userCfg, ... }:
    let
      profile = "${homeOf username}/${host.profile}";
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !userCfg.omo.enable;
            message = "Enable limi-suite or omo, not both: both install `omo` and write ~/.omo.";
          }
        ];
        home = {
          sessionPath = [ "${profile}/bin" ];
          # `limi pin` runs nix-env from PATH; hand it this host's nix.
          activation.limiProfile = {
            after = [ "writeBoundary" ];
            before = [ ];
            data = ''
              run env PATH="${pkgs.nix}/bin:$PATH" ${pinned}/bin/limi pin ${pinned}
            '';
          };
        };
      }
      # The suite's tmux config and status-bar widget, read through the
      # profile so `limi switch` updates them too, plus the window icon for
      # omo panes.
      (lib.mkIf userCfg.tmux.enable {
        programs.tmux.extraConfig = "source-file -q ${profile}/${host.tmuxConf}";
        xdg.configFile = {
          # Appends to the `icons:` map cli/tmux/theme.nix writes, so it must
          # land after it. Glyph is U+F51B, chosen by hand: keep it.
          "tmux/tmux-nerd-font-window-name.yml".text = lib.mkAfter "  omo: \"\"";
          "tmux/widgets/10-limi" = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              exec ${profile}/${host.tmuxWidget} "$@"
            '';
          };
        };
      })
    ];
}
