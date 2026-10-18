# SMART health monitoring for every detected disk (polaris: Samsung 980 Pro
# NVMe), so a failing drive warns before it dies.
#
# smartd runs as root, so its warning has to cross into the user session:
# systembus-notify relays it from the system bus to the session's
# notification daemon (noctalia under niri). Wall stays on as the fallback
# for a headless box (server-mode) where nobody watches a desktop.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "smartd";
  config.services.smartd = {
    enable = true;
    notifications.systembus-notify.enable = true;
  };
}
