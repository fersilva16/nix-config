{ pkgs, config, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;

    extensions = (with pkgs.vscode-extensions; [
      rust-lang.rust-analyzer
      eamodio.gitlens
    ]) ++ pkgs.my-vscode-extensions.allExtensions;

    # keybindings = import ./keybindings.nix;
    # userSettings = import ./settings.nix;
  };

  home.file.".config/Code/User/settings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/vscode/settings.json";
  };

  home.file.".config/Code/User/keybindings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/vscode/keybindings.json";
  };
}
