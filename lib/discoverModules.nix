# Filesystem-based module auto-discovery for mkUserModule modules.
#
# Scans modulesDir for category directories and discovers modules following
# the project convention:
#   - <category>/<app>.nix       → imported directly
#   - <category>/<app>/<app>.nix → directory module entry point
#
# Non-.nix files and sub-files within directory modules (parts, configs) are
# ignored — they're imported by their parent entry point.
#
# By default excludes: hosts, users, linux.
{ lib }:
{
  modulesDir,
  exclude ? [
    "hosts"
    "users"
    "linux"
  ],
}:
let
  entries = builtins.readDir modulesDir;

  discoverCategory =
    name: type:
    if type != "directory" || builtins.elem name exclude then
      [ ]
    else
      let
        categoryPath = modulesDir + "/${name}";
        categoryEntries = builtins.readDir categoryPath;
      in
      lib.concatLists (
        lib.mapAttrsToList (
          entryName: entryType:
          if entryType == "regular" && lib.hasSuffix ".nix" entryName then
            [ (categoryPath + "/${entryName}") ]
          else if entryType == "directory" then
            let
              entryPoint = categoryPath + "/${entryName}/${entryName}.nix";
            in
            if builtins.pathExists entryPoint then [ entryPoint ] else [ ]
          else
            [ ]
        ) categoryEntries
      );
in
lib.concatLists (lib.mapAttrsToList discoverCategory entries)
