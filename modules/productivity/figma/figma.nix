{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  figma-developer-mcp = pkgs.callPackage ./figma-developer-mcp.nix { };
in
mkUserModule {
  name = "figma";
  casks = [ "figma" ];
  # Figma token scopes required: File content (file_content:read) and
  # Dev resources (file_dev_resources:read), in ~/.config/figma/.env.
  home =
    { userCfg, ... }:
    {
      home.file.".omo/agent/extensions/figma-mcp.ts" = lib.mkIf userCfg.omo.enable {
        source = pkgs.replaceVars ./figma-mcp.ts {
          figmaMcp = "${figma-developer-mcp}/bin/figma-developer-mcp";
        };
      };
    };
}
