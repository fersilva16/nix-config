{ pkgs }:
let
  figma-developer-mcp = pkgs.callPackage ./figma-developer-mcp.nix { };
in
{
  default = true;
  home =
    { username, ... }:
    {
      programs.opencode.settings.mcp.framelink = {
        enabled = false;
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
