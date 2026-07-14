# polaris user composition — first wave is CLI-only (plan Phase 1 grows this).
{ mkUser, ... }:
mkUser {
  name = "fernando";
  bat.enable = true;
  hyprland.enable = true;
}
