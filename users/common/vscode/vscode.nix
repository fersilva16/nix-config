{ pkgs, lib, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    extensions = pkgs.my-vscode-extensions.allExtensions;

    keybindings = import ./keybindings.nix;

    userSettings = import ./settings.nix;
  };
}
