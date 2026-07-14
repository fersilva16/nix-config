{
  mkSystemModule,
  inputs,
  ...
}:
let
  inherit (inputs)
    homebrew-core
    homebrew-cask
    homebrew-bundle
    homebrew-schpet-tap
    ;
in
mkSystemModule {
  name = "homebrew";
  config =
    { config, ... }:
    {
      nix-homebrew = {
        enable = true;
        enableRosetta = true;
        user = config.system.primaryUser;

        taps = {
          "homebrew/homebrew-core" = homebrew-core;
          "homebrew/homebrew-cask" = homebrew-cask;
          "homebrew/homebrew-bundle" = homebrew-bundle;
          "schpet/homebrew-tap" = homebrew-schpet-tap;
        };

        mutableTaps = false;
      };

      homebrew = {
        enable = true;
        onActivation.cleanup = "zap";
        taps = builtins.attrNames config.nix-homebrew.taps;
      };
    };
}
