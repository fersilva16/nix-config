{ pkgs, config, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    extensions = pkgs.my-vscode-extensions.allExtensions;

    # keybindings = import ./keybindings.nix;
    # userSettings = import ./settings.nix;
  };

  home.file.".config/VSCodium/User/settings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/vscode/settings.json";
  };

  home.file.".config/VSCodium/User/keybindings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/vscode/keybindings.json";
  };
}
