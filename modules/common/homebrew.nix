{ username, inputs, config, ... }:
let
  inherit (inputs) homebrew-core homebrew-cask homebrew-bundle;
in
{
  nix-homebrew = {
    enable = true;

    enableRosetta = true;

    user = username;

    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
      "homebrew/homebrew-bundle" = homebrew-bundle;
    };

    mutableTaps = false;
  };

  homebrew = {
    enable = true;

    onActivation.cleanup = "zap";

    taps = builtins.attrNames config.nix-homebrew.taps;
  };
}
