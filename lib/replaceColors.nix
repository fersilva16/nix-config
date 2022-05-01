{ config }:
let
  keys = builtins.map (k: "%${k}%") (builtins.attrNames config.colors);
  values = builtins.attrValues config.colors;
in
builtins.replaceStrings keys values
