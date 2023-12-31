{ pkgs, lib, ... }:
{
  home.activation = {
    defaultShell = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      sudo chsh -s /run/current-system/sw${pkgs.fish.shellPath} $USER
    '';
  };
}