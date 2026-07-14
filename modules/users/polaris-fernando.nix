# polaris user composition — first wave is CLI-only (plan Phase 1 grows this).
{ mkUser, ... }:
mkUser {
  name = "fernando";
  bat.enable = true;
  feh.enable = true;
  flameshot.enable = true;
  hyprland.enable = true;
  i3.enable = true;
}
