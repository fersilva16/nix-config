pkgs: {
  paisa = pkgs.callPackage ./paisa.nix { };
  flexoki-tmux = pkgs.callPackage ./flexoki-tmux/flexoki-tmux.nix { };
  tmux-extras = pkgs.callPackage ./tmux-extras/tmux-extras.nix { };
}
