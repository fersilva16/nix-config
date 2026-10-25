# The Figma app. Its MCP extension for omo ships in Nalum (Limi).
{ mkUserModule, ... }:
mkUserModule {
  name = "figma";
  casks = [ "figma" ];
}
