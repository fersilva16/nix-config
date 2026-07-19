# Noctalia — desktop shell for niri (bar, launcher, notifications, lock
# screen, control center, wallpaper, OSDs). Replaces the previous
# waybar/fuzzel/swaync/swaylock stack in one cohesive layer.
#
# Pinned to the stable v4 line (quickshell-based); see the flake input.
#
# Deliberately NOT importing noctalia's home-manager module: its only real
# value is a declarative settings.json, which becomes a read-only symlink
# and blocks tuning from the in-shell settings GUI while the setup is
# still being explored. Noctalia manages its own mutable ~/.config/noctalia.
# ponytail: import inputs.noctalia.homeModules.default and freeze settings
# once the GUI-tuned config stabilizes (copy via Settings -> General ->
# Copy Settings).
#
# The niri-side glue (spawn-at-startup, IPC keybinds, layer rules) lives in
# modules/linux/niri.nix, which owns config.kdl.
{
  mkUserModule,
  inputs,
  system,
  ...
}:
mkUserModule {
  name = "noctalia";
  # All shell glue lives in niri's config.kdl — useless without niri here.
  requires = [ "niri" ];
  system = {
    # Pre-built binaries for noctalia + its quickshell fork.
    nix.settings = {
      extra-substituters = [ "https://noctalia.cachix.org" ];
      extra-trusted-public-keys = [
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      ];
    };
    # Power widgets need these; NetworkManager + bluetooth are already
    # host-wide modules.
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
  };
  home = {
    home.packages = [ inputs.noctalia.packages.${system}.default ];
  };
}
