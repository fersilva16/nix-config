{ username, inputs, ... }:
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
      "homebrew/bundle" = homebrew-bundle;
    };

    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
  };
}
