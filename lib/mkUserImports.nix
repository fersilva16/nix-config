{ lib, inputs, ... }@args:
let
  inherit (inputs) home-manager;
in
username: imports:
lib.forEach imports (imp: import imp (args // { inherit (home-manager) lib; inherit username; }))
