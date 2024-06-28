pkgs:
{
  my-vscode-extensions = pkgs.callPackage ./my-vscode-extensions/my-vscode-extensions.nix { };
  paisa = pkgs.callPackage ./paisa.nix { };
}
