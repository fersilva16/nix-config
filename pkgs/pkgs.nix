{ self }:
{
  font-awesome_6 = self.callPackage ./font-awesome_6/font-awesome_6.nix { };

  my-vscode-extensions = self.callPackage ./my-vscode-extensions/my-vscode-extensions.nix { };

  responsively = self.callPackage ./responsively.nix { };
}
