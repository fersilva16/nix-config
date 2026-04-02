{ pkgs }:
let
  figma-developer-mcp = pkgs.callPackage ./figma-developer-mcp.nix { };
in
{
  default = false;
  home =
    { username, ... }:
    {
      programs.opencode.settings.mcp.framelink = {
        enabled = true;
        type = "local";
        command = [
          "${figma-developer-mcp}/bin/figma-developer-mcp"
          "--stdio"
          "--env"
          "/Users/${username}/.config/figma/.env"
        ];
      };
    };
}
