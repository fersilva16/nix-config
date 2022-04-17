{ pkgs }:
{
  node = import ./node.nix { inherit pkgs; };

  haskell = import ./haskell.nix { inherit pkgs; };

  rust = import ./rust.nix { inherit pkgs; };
}
