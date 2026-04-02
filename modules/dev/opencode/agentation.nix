{ pkgs }:
let
  agentation-mcp = pkgs.callPackage ./agentation-mcp.nix { };
in
{
  default = false;
  home = {
    programs.opencode.settings.mcp.agentation = {
      enabled = true;
      type = "local";
      command = [
        "${agentation-mcp}/bin/agentation-mcp"
        "server"
      ];
    };
  };
}
