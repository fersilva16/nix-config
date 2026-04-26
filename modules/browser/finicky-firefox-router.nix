# Finicky → Firefox active-profile router.
#
# Builds a tiny stub `.app` at /Applications/<appName>.app whose only job is
# to inspect the running macOS app graph and forward an incoming URL to
# whichever Firefox profile bundle (org.mozilla.firefox.<profile>) is
# currently most active. Set Finicky's `defaultBrowser` to this app's path
# and the "default fallback" route stops being a fixed profile — it follows
# the user instead.
#
# Architecture:
#   Finicky.app (system default URL handler)
#     → routes via handlers; un-handled URLs go to defaultBrowser
#     → defaultBrowser is "/Applications/Hammerspoon.app"
#   Hammerspoon.app (claims http/https in its stock Info.plist)
#     → URL Apple Event arrives at hs.urlevent.httpCallback
#     → callback (this module's extras Lua) picks the active Firefox bundle
#       from in-memory state and dispatches via hs.urlevent.openURLWithBundle
#   Per-profile Firefox bundle
#     → receives URL via standard macOS Apple Event delivery and opens it
#       in the right profile (works because every profile has its own
#       MOZ_APP_REMOTINGNAME — see firefox/profile-apps.nix)
#
# Detection cascade (in the Lua callback, all in-memory):
#   1. lastActiveFirefox (updated in real-time by hs.application.watcher) is
#      still running → route there. Catches the common case where the user
#      was just in Telepatia, switched to Slack/Discord to click a link, and
#      now Slack/Discord is frontmost.
#   2. Any Firefox profile bundle is running → route to the first one
#      hs.application.runningApplications() returns.
#   3. Nothing matches → route to the configured `fallbackBundle`.
#
# Why Hammerspoon and not a stub .app:
#   Hammerspoon is already running with persistent in-memory state, so
#   routing happens with zero subprocess overhead (~5ms total vs ~350ms
#   for the previous AppleScript-bundle wrapper). Hammerspoon also already
#   claims http/https in its Info.plist (it ships that way), so we don't
#   need to mutate any installed app's plist or re-sign anything.
#
# Why this works alongside the per-profile firefox bundles:
#   Each profile is its own .app with bundle ID `org.mozilla.firefox.<name>`
#   (see modules/browser/firefox/profile-apps.nix). hs.urlevent.openURLWithBundle
#   targets the bundle id directly via LaunchServices, triggering each
#   profile's existing compatibility.ini self-heal launcher transparently.
#
# Caveats:
#   - Hammerspoon must be running. If it isn't, URLs falling through to
#     Finicky's defaultBrowser have nowhere to go. (Hammerspoon is a launchd
#     agent in this config, so this is unlikely in practice.)
#   - We declare a runtime dependency on the `hammerspoon` capability via
#     `requires` so enabling this module auto-enables hammerspoon too.
#   - Disabling this module leaves the extras Lua at
#     ~/.hammerspoon/extras/finicky-firefox-router-tracker.lua behind.
#     Remove it manually if you no longer want the URL handler installed.
{
  mkUserModule,
  lib,
  pkgs,
  ...
}:
let
  defaultBrowserPath = "/Applications/Hammerspoon.app";
in
mkUserModule {
  name = "finicky-firefox-router";

  # Pure capability — useless without finicky to route through, firefox
  # profile bundles to route to, and hammerspoon to receive URL events.
  requires = [
    "finicky"
    "firefox"
    "hammerspoon"
  ];

  extraOptions = {
    fallbackBundle = lib.mkOption {
      type = lib.types.str;
      default = "org.mozilla.firefox";
      example = "org.mozilla.firefox.personal";
      description = ''
        Bundle identifier of the Firefox profile to route URLs to when no
        profile bundle is currently running. Match a `bundleId` declared
        under `firefox.profileApps.profiles.<name>.bundleId`.
      '';
    };

    defaultBrowserPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = defaultBrowserPath;
      description = ''
        Path to set as Finicky's `defaultBrowser` so URLs land at this
        module's URL receiver. Hammerspoon already claims http/https in its
        stock Info.plist; the extras Lua installs the actual handler.
      '';
    };
  };

  home =
    { cfg, ... }:
    let
      # Combined tracker + router Lua snippet, loaded into Hammerspoon by
      # init.lua's extras loader. Real-time activation tracking + http/https
      # URL receiver in one place; all in-memory, no subprocesses.
      routerLua = pkgs.writeText "finicky-firefox-router.lua" ''
        -- Active-profile router for finicky-firefox-router. Hammerspoon is
        -- Finicky's defaultBrowser target; this snippet is what actually
        -- handles incoming http/https URL events and dispatches them to the
        -- right Firefox profile bundle.

        local FALLBACK_BUNDLE = ${builtins.toJSON cfg.fallbackBundle}
        local FIREFOX_PROFILE_PATTERN = "^org%.mozilla%.firefox%..+"

        -- In-memory cache of the most recently activated Firefox profile
        -- bundle id. Updated by the activation watcher; consulted by the URL
        -- callback. nil until the user focuses a Firefox profile at least
        -- once after Hammerspoon (re)load.
        local lastActiveFirefox = nil

        -- Used to retain watchers + callback bindings across hs.reload(),
        -- otherwise the GC drops them and notifications stop firing. Same
        -- _G.__<name>Retain pattern as init.lua's _G.__hsHyperRetain.
        _G.__finickyFirefoxRouterRetain = _G.__finickyFirefoxRouterRetain or {}
        local retain = _G.__finickyFirefoxRouterRetain

        -- Walk hs.application.runningApplications() once and return the
        -- first bundle id that matches a Firefox profile pattern (or nil).
        local function firstRunningFirefox()
          for _, app in ipairs(hs.application.runningApplications()) do
            local bid = app:bundleID()
            if bid and bid:match(FIREFOX_PROFILE_PATTERN) then
              return bid
            end
          end
          return nil
        end

        local function isRunning(bundleId)
          if not bundleId then return false end
          for _, app in ipairs(hs.application.runningApplications()) do
            if app:bundleID() == bundleId then return true end
          end
          return false
        end

        -- Activation watcher: keep lastActiveFirefox in sync with whichever
        -- Firefox profile bundle the user most recently focused.
        if retain.watcher then retain.watcher:stop() end
        retain.watcher = hs.application.watcher.new(function(_, eventType, app)
          if eventType ~= hs.application.watcher.activated then return end
          if not app then return end
          local bid = app:bundleID()
          if bid and bid:match(FIREFOX_PROFILE_PATTERN) then
            lastActiveFirefox = bid
          end
        end)
        retain.watcher:start()

        -- URL receiver: Finicky's defaultBrowser is /Applications/Hammerspoon.app,
        -- so http/https URLs that fall through Finicky's explicit handlers
        -- arrive here as kInternetEventClass / kAEGetURL Apple Events. We
        -- pick the active Firefox profile and hand the URL off via
        -- hs.urlevent.openURLWithBundle (LaunchServices bundle-id dispatch,
        -- bypasses the global URL handler so we don't loop back through
        -- Finicky).
        hs.urlevent.httpCallback = function(_scheme, _host, _params, fullURL, _senderPID)
          local target = (isRunning(lastActiveFirefox) and lastActiveFirefox)
            or firstRunningFirefox()
            or FALLBACK_BUNDLE
          hs.urlevent.openURLWithBundle(fullURL, target)
        end
      '';
    in
    {
      home.file.".hammerspoon/extras/finicky-firefox-router.lua".source = routerLua;

      # Best-effort cleanup of the previous architecture's artifacts so users
      # upgrading from the AppleScript-bundle wrapper get a clean state.
      # (home-manager doesn't track files outside ~ and we have no built-in
      # uninstall hook — this just keeps /Applications tidy on rebuild.)
      home.activation.finickyFirefoxRouterCleanup = ''
        if [ -d "/Applications/Firefox Active.app" ]; then
          /bin/rm -rf "/Applications/Firefox Active.app"
        fi
        # Old extras filename; renamed to drop the "-tracker" suffix now that
        # the snippet does both tracking and URL routing.
        if [ -e "$HOME/.hammerspoon/extras/finicky-firefox-router-tracker.lua" ]; then
          /bin/rm -f "$HOME/.hammerspoon/extras/finicky-firefox-router-tracker.lua"
        fi
      '';
    };
}
