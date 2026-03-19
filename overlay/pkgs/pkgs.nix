pkgs: {
  paisa = pkgs.callPackage ./paisa.nix { };
  flexoki-tmux = pkgs.callPackage ./flexoki-tmux/flexoki-tmux.nix { };
  tmux-extras = pkgs.callPackage ./tmux-extras/tmux-extras.nix { };
  tmux-nerd-font-window-name =
    pkgs.callPackage ./tmux-nerd-font-window-name/tmux-nerd-font-window-name.nix
      { };
  figma-developer-mcp = pkgs.callPackage ./figma-developer-mcp.nix { };
  linear-cli = pkgs.callPackage ./linear-cli.nix { };
}
