{ pkgs }:
let
  figma-developer-mcp = pkgs.callPackage ./figma-developer-mcp.nix { };
in
{
  default = true;
  home =
    { username, ... }:
    {
      # Figma token scopes required: File content (file_content:read)
      # and Dev resources (file_dev_resources:read).
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
