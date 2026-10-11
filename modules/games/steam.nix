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
    linux = {
      programs.steam = {
        enable = true;
        # Proton-GE shows up in Properties > Compatibility next to Valve's Proton.
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
      # Steam's CHTTPClientThread (and some Proton games) take split-lock
      # traps every few seconds; the default mitigation sleeps the offending
      # thread on each one. SteamOS/Bazzite ship this off too.
      boot.kernel.sysctl."kernel.split_lock_mitigate" = 0;
    };
  };
}
