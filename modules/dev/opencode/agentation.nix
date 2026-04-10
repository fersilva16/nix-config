{ pkgs }:
let
  agentation-mcp = pkgs.callPackage ./agentation-mcp.nix { };
in
{
  default = true;
  home = {
    programs.opencode.settings.mcp.agentation = {
      enabled = false;
      type = "local";
      command = [
        "${agentation-mcp}/bin/agentation-mcp"
        "server"
      ];
    };
  };
}
