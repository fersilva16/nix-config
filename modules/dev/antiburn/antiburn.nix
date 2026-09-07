{
  mkUserModule,
  pkgs,
  ...
}:
mkUserModule {
  name = "antiburn";

  # Built from source rather than the released .app so the OpenCode scan fix
  # can be patched in; see package.nix for what that costs.
  home.home.packages = [ (pkgs.callPackage ./package.nix { }) ];
}
