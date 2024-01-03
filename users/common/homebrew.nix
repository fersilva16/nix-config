{ inputs, ... }:
let
  inherit (inputs) homebrew-core homebrew-cask homebrew-bundle;
in
{
  nix-homebrew = {
    enable = true;

    enableRosetta = true;

    user = "fernando";

    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
      "homebrew/bundle" = homebrew-bundle;
    };

    mutableTaps = false;
  };

  homebrew = {
    enable = true;

    brews = [
      "gpg"
      "pinentry-mac"
      "mongosh"
      "kubectl"
    ];

    casks = [
      "google-chrome"
      "discord"
      "slack"
      "obsidian"
      "bitwarden"
      "whatsapp"
      "studio-3t"
      "visual-studio-code"
      "raycast"
      "cloudflare-warp"
      "calibre"
      "orbstack"
    ];
  };
}
