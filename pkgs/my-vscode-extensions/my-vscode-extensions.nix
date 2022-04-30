{ lib, vscode-utils }:
let
  extensions = import ./extensions.nix;
  extensionToPackage = mktplcRef:
    vscode-utils.buildVscodeMarketplaceExtension { inherit mktplcRef; };

  extensionToNameValuePair = extension:
    lib.nameValuePair
      extension.name
      (extensionToPackage extension);
in
{
  allExtensions = map extensionToPackage extensions;
} // lib.listToAttrs (map extensionToNameValuePair extensions)
