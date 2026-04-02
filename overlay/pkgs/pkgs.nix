pkgs: {
  agentation-mcp = pkgs.callPackage ./agentation-mcp.nix { };
  paisa = pkgs.callPackage ./paisa.nix { };
  figma-developer-mcp = pkgs.callPackage ./figma-developer-mcp.nix { };
  linear-cli = pkgs.callPackage ./linear-cli.nix { };
  readwise-cli = pkgs.callPackage ./readwise-cli.nix { };
}
