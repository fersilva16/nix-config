# Firefox — installed as a secondary browser via Homebrew cask.
#
# Chrome is the primary browser (see chrome.nix + finicky.nix). Firefox is
# kept around as a plain cask with no per-profile .app bundles or URL routing.
{ mkUserModule, ... }:
mkUserModule {
  name = "firefox";
  casks = [ "firefox" ];
}
