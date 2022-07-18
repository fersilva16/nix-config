pkgs:
{
  font-awesome_6 = pkgs.callPackage ./font-awesome_6/font-awesome_6.nix { };

  my-vscode-extensions = pkgs.callPackage ./my-vscode-extensions/my-vscode-extensions.nix { };

  responsively = pkgs.callPackage ./responsively.nix { };

  tlauncher = pkgs.callPackage ./tlauncher.nix { };
}
