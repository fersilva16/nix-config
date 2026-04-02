{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  readwise-cli = pkgs.buildNpmPackage rec {
    pname = "readwise-cli";
    version = "0.5.5";

    src = pkgs.fetchFromGitHub {
      owner = "readwiseio";
      repo = "readwise-cli";
      tag = "v${version}";
      hash = "sha256-oPyhsKyaZRogn5y1JIJH0js0yrk5E298QEpIC9/4xXc=";
    };

    npmDepsHash = "sha256-eupjqOEE77pNzY9DBJdYdDraJtUVhbojaG/QCW+m+jw=";

    meta = {
      description = "CLI for Readwise and Reader — search, read, and organize from the terminal";
      homepage = "https://github.com/readwiseio/readwise-cli";
      license = lib.licenses.unfree;
      mainProgram = "readwise";
    };
  };
in
mkUserModule {
  name = "readwise";
  home.home.packages = [ readwise-cli ];
}
