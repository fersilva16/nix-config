# dualsense: `dualsense-pair` takes the controller back from the PS5.
#
# Hold Create + PS on the controller, run `dualsense-pair`, and it drops the
# stale entry, scans, then pairs, trusts and connects. Going back to the PS5
# needs only a cable plugged into the PS5 once.
{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
let
  dualsense-pair = pkgs.writeShellApplication {
    name = "dualsense-pair";
    runtimeInputs = [
      pkgs.bluez
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ./dualsense-pair.sh;
  };
in
mkUserModule {
  name = "dualsense";
  home.home.packages = forPlatform { linux = [ dualsense-pair ]; };
}
