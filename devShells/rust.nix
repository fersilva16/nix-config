{ pkgs }:

with pkgs;

mkShell {
  buildInputs = [
    cargo
  ];
}
