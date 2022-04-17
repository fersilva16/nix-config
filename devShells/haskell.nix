{ pkgs }:

with pkgs;

mkShell {
  buildInputs = [
    haskell-language-server
    cabal-install
    ghc
  ];
}
