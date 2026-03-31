# forPlatform — platform-aware value selector.
#
# Selects a value based on the current system platform. When only one
# platform is specified, the other side's identity value is inferred
# from the provided value's type (e.g., "" for strings, [] for lists,
# {} for attrsets).
#
# Signature: system -> { darwin?, linux? } -> value
#
# Usage:
#
#   # Both platforms — explicit values:
#   forPlatform { darwin = "/Users/${u}"; linux = "/home/${u}"; }
#
#   # Single platform — identity inferred for the other:
#   forPlatform { darwin = "ssh-add --apple-load-keychain"; }  # linux → ""
#   forPlatform { linux = [ pkgs.xclip ]; }                    # darwin → []
#   forPlatform { darwin = { homebrew.casks = [ "slack" ]; }; } # linux → {}
#
# Composable with existing tools — does NOT merge, only selects:
#
#   # Strings: interpolation
#   ''
#     shared line
#     ${forPlatform { darwin = "darwin-only line"; }}
#   ''
#
#   # Lists: concatenation
#   [ sharedPkg ] ++ forPlatform { darwin = [ pkgs.iterm2 ]; }
#
#   # Attrsets: lib.mkMerge
#   lib.mkMerge [
#     { shared config }
#     (forPlatform { darwin = { homebrew.casks = [ "slack" ]; }; })
#   ]
#
system:
let
  isDarwin = builtins.match ".*-darwin" system != null;

  identityFor =
    value:
    let
      type = builtins.typeOf value;
    in
    if type == "string" then
      ""
    else if type == "list" then
      [ ]
    else if type == "set" then
      { }
    else if type == "bool" then
      false
    else if type == "int" then
      0
    else
      throw "forPlatform: cannot infer identity for type '${type}' — provide both platforms explicitly";
in
{
  darwin ? null,
  linux ? null,
}:
let
  selected = if isDarwin then darwin else linux;
  other = if isDarwin then linux else darwin;
in
if selected != null then
  selected
else if other != null then
  identityFor other
else
  throw "forPlatform: at least one platform must be specified"
