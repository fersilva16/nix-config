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
    onActivation.cleanup = "zap";

    brews = [
      "gpg"
      "pinentry-mac"
    ];

    casks = [
      "microsoft-excel"
      "google-chrome"
      "discord"
      "obsidian"
      "whatsapp"
      "studio-3t"
      "visual-studio-code"
      "raycast"
      "calibre"
      "orbstack"
      "whisky"
      "postman"
      "selfcontrol"
      "zoom"
      "zed"
      "iina"
      "warp"
    ];
  };
}
