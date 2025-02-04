{
  config,
  lib,
  pkgs,
  ...
}:
{
  disabledModules = [ "targets/darwin/linkapps.nix" ];

  home.activation = {
    copyApplications =
      let
        apps = pkgs.buildEnv {
          name = "home-manager-applications";
          paths = config.home.packages;
          pathsToLink = "/Applications";
        };
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        baseDir="$HOME/Applications/Home Manager Apps"

        if [ -d "$baseDir" ]; then
          rm -rf "$baseDir"
        fi

        mkdir -p "$baseDir"

        for appFile in ${apps}/Applications/*; do
          target="$baseDir/$(basename "$appFile")"

          echo "$target"

          $DRY_RUN_CMD cp ''${VERBOSE_ARG:+-v} -fHRL "$target" "$baseDir"
          $DRY_RUN_CMD chmod ''${VERBOSE_ARG:+-v} -R +w "$target"
        done
      '';
  };
}
