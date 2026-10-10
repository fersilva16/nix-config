{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
mkUserModule {
  name = "steam";
  casks = [ "steam" ];
  # NixOS module wires the FHS runtime, 32-bit libs and udev rules for
  # controllers; a bare pkgs.steam in home.packages misses those.
  system = forPlatform {
    linux.programs.steam = {
      enable = true;
      # Proton-GE shows up in Properties > Compatibility next to Valve's Proton.
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
  };
}
