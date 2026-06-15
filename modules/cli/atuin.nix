{ mkUserModule, ... }:
mkUserModule {
  name = "atuin";
  home = {
    programs.atuin = {
      enable = true;

      enableFishIntegration = true;

      # Keep fish's native up-arrow history (preserves muscle memory); bind
      # atuin's fuzzy search to Ctrl-R only.
      flags = [ "--disable-up-arrow" ];

      # Local-first: no sync configured (atuin only syncs after an explicit
      # `atuin login`). History stays on-device.
      settings = {
        style = "compact";
        inline_height = 25;
        show_preview = true;
        # Updates are managed by Nix; skip atuin's own update nag.
        update_check = false;
      };
    };
  };
}
