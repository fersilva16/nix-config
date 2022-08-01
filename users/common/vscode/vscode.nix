{ pkgs, config, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;

    extensions = pkgs.my-vscode-extensions.allExtensions ++ (with pkgs.vscode-extensions; [ rust-lang.rust-analyzer ]);

    # keybindings = import ./keybindings.nix;
    # userSettings = import ./settings.nix;
  };

  home.file.".config/Code/User/settings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink ./settings.json;
  };

  home.file.".config/Code/User/keybindings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink ./keybindings.json;
  };
}
