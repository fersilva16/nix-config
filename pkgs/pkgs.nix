pkgs:
{
  my-vscode-extensions = pkgs.callPackage ./my-vscode-extensions/my-vscode-extensions.nix { };

  responsively = pkgs.callPackage ./responsively.nix { };

  tlauncher = pkgs.callPackage ./tlauncher.nix { };
}
