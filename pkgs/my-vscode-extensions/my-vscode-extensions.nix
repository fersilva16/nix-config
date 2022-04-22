{ lib, vscode-utils }:
let
  extensions = import ./extensions.nix;
  extensionToPackage = (extension:
    vscode-utils.buildVscodeMarketplaceExtension { mktplcRef = extension; }
  );

  extensionToNameValuePair = (extension:
    lib.nameValuePair
      extension.name
      (extensionToPackage extension)
  );
in
{
  allExtensions = map extensionToPackage extensions;
} // lib.listToAttrs (map extensionToNameValuePair extensions)
