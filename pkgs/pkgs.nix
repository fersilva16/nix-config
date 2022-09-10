pkgs:
{
  my-vscode-extensions = pkgs.callPackage ./my-vscode-extensions/my-vscode-extensions.nix { };

  responsively = pkgs.callPackage ./responsively.nix { };

  mov-cli = pkgs.callPackage ./mov-cli.nix { };

  bookcut = pkgs.callPackage ./bookcut.nix { };
}
