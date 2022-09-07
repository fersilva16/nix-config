pkgs:
{
  my-vscode-extensions = pkgs.callPackage ./my-vscode-extensions/my-vscode-extensions.nix { };

  responsively = pkgs.callPackage ./responsively.nix { };

  bs4 = pkgs.callPackage ./mov-cli/bs4.nix { };

  mov-cli = pkgs.callPackage ./mov-cli/mov-cli.nix { };
}
