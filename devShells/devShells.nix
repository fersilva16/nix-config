{ pkgs }:
{
  node = import ./node.nix { inherit pkgs; };

  haskell = import ./haskell.nix { inherit pkgs; };
}
