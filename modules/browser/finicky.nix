# Finicky — macOS URL router.
#
# Finicky registers itself as the system default browser and routes every
# opened URL to a user-declared target browser based on URL pattern and/or
# the source app the URL was opened from. Use per-handler `profile` (and
# `defaultBrowserProfile`) to send work URLs to one browser profile and
# personal URLs to another.
#
# After rebuild: open Finicky once (from /Applications), then set it as the
# default browser via System Settings → Desktop & Dock → Default web browser.
{ mkUserModule, lib, ... }:
mkUserModule {
  name = "finicky";

  extraOptions = {
    defaultBrowser = lib.mkOption {
      type = lib.types.str;
      default = "/Applications/Firefox.app";
      description = ''
        Browser used when no handler matches. Accepts an app name
        ("Google Chrome"), a bundle id, or a full `.app` path. Prefer full
        paths for bundles with spaces (e.g. "/Applications/Firefox Personal.app").
      '';
    };

    defaultBrowserProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Personal";
      description = ''
        Profile to open in `defaultBrowser` for Chromium/Firefox browsers.
        Use the profile's *display name* as shown in the browser's profile
        menu (e.g. "Personal"), not its on-disk directory ("Profile 2") —
        Finicky resolves the name via the browser's Local State.
      '';
    };

    hideIcon = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Hide Finicky from the macOS menu bar. Finicky still runs in the
        background and routes URLs; you just lose the status bar icon.
        Backed by Finicky's native `options.hideIcon` setting (v4.2.1+).
      '';
    };

    handlers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            match = lib.mkOption {
              type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
              default = [ ];
              description = ''
                URL glob pattern(s) (e.g. "*.slack.com/*"). A list is
                OR-combined. Leave empty when matching purely on `fromApp`.
              '';
            };
            fromApp = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Bundle identifier of the source app the URL was opened from.
                When set, the handler matches any URL opened from this app.
                Combines (OR) with `match` if both are set.

                Find bundle IDs with:
                  mdls -name kMDItemCFBundleIdentifier /Applications/<App>.app

                Common examples:
                  "com.tinyspeck.slackmacgap" — Slack
                  "com.apple.mail"            — Apple Mail
                  "com.readdle.smartemail-Mac" — Spark
                  "com.raycast.macos"         — Raycast
                  "com.microsoft.VSCode"      — VS Code
                  "com.linear"                — Linear
              '';
            };
            browser = lib.mkOption {
              type = lib.types.str;
              description = ''
                Target browser. Accepts an app name ("Google Chrome"), a
                bundle id, or a full `.app` path. Full `.app` path recommended
                for custom Firefox profile bundles.
              '';
            };
            profile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "Telepatia";
              description = ''
                Browser profile to open for this handler (Chromium/Firefox).
                Use the profile's *display name* from the browser's profile
                menu (e.g. "Telepatia"), not its on-disk directory
                ("Profile 1"); Finicky resolves the name and passes
                `--profile-directory`.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        URL routing rules, checked in order. First match wins. Falls back to
        `defaultBrowser` if nothing matches.
      '';
    };

    rewrites = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            match = lib.mkOption {
              type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
              description = "URL pattern(s) to rewrite.";
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = "Rewritten URL.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        URL rewrite rules applied before handler matching. Useful for
        stripping trackers or normalising links before routing.
      '';
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Raw JavaScript appended after the generated config. Use for anything
        the typed options above don't cover (regex matchers, complex functions).
      '';
    };
  };

  system.homebrew.casks = [ "finicky" ];

  home =
    { cfg, lib, ... }:
    let
      asList = v: if builtins.isList v then v else [ v ];

      # Render a browser target as a JS value. With a profile it becomes a
      # Finicky browser object `{ name, profile }` (profile → --profile-directory
      # for Chromium, --profile for Firefox); without one it stays a bare
      # string so existing path-only configs render unchanged.
      renderBrowser =
        name: profile:
        if profile != null then
          "{ name: ${builtins.toJSON name}, profile: ${builtins.toJSON profile} }"
        else
          builtins.toJSON name;

      # Render a single handler as a JS object literal.
      # Combines `match` URL globs with the optional `fromApp` opener check via
      # Finicky's OR-list match. Throws if both are empty — we don't silently
      # generate a dead handler.
      renderHandler =
        h:
        let
          urlPatterns = lib.filter (p: p != "") (asList h.match);
          openerExpr = lib.optional (
            h.fromApp != null
          ) "(_, { opener }) => opener != null && opener.bundleId === ${builtins.toJSON h.fromApp}";
          matchExprs = map builtins.toJSON urlPatterns ++ openerExpr;
          matchValue =
            if matchExprs == [ ] then
              throw "finicky handler requires `match` or `fromApp`: ${builtins.toJSON h}"
            else if builtins.length matchExprs == 1 then
              builtins.head matchExprs
            else
              "[ ${builtins.concatStringsSep ", " matchExprs} ]";
        in
        "{ match: ${matchValue}, browser: ${renderBrowser h.browser h.profile} }";

      renderRewrite =
        r:
        let
          urlPatterns = asList r.match;
          matchJs = builtins.toJSON (
            if builtins.length urlPatterns == 1 then builtins.head urlPatterns else urlPatterns
          );
        in
        "{ match: ${matchJs}, url: ${builtins.toJSON r.url} }";

      handlersJs = builtins.concatStringsSep ",\n    " (map renderHandler cfg.handlers);
      rewritesJs = builtins.concatStringsSep ",\n    " (map renderRewrite cfg.rewrites);

      sections = [
        "defaultBrowser: ${renderBrowser cfg.defaultBrowser cfg.defaultBrowserProfile}"
      ]
      ++ lib.optional cfg.hideIcon "options: { hideIcon: true }"
      ++ [ "handlers: [\n    ${handlersJs}\n  ]" ]
      ++ lib.optional (cfg.rewrites != [ ]) "rewrite: [\n    ${rewritesJs}\n  ]";

      body = builtins.concatStringsSep ",\n  " sections;
    in
    {
      # Finicky searches ~/.finicky.js first.
      home.file.".finicky.js".text = ''
        // Generated by nix-darwin — edits will be overwritten on rebuild.
        // Modify via modules.users.<user>.finicky.* in your user config.
        export default {
          ${body}
        };

        ${cfg.extraConfig}
      '';
    };
}
