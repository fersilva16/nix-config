# nalum — personal Hermes Agent workspace.
#
# Installs the Hermes Agent CLI and points HERMES_HOME at ~/nalum, where
# every personal bit lives (SOUL.md, AGENTS.md, config.yaml, .env, skills/,
# plugins/, dashboard-themes/, etc.) — version-controlled in its own
# private repo, never in this public nix-config.
#
# The directory-existence safety check runs at darwin-rebuild activation
# time (not eval time): an absent ~/nalum surfaces as a loud warning during
# the switch, but doesn't block the rebuild. Eval-time gating would require
# `--impure`, which we avoid so plain `darwin-rebuild switch --flake .#m1`
# keeps working.
#
# Hermes optional extras: upstream's default build excludes optional
# dependency groups because Hermes normally lazy-installs them via pip at
# runtime — which fails on Nix's read-only store. We declaratively include
# the groups we use:
#
#   messaging — discord.py, python-telegram-bot, slack-bolt (gateway adapters)
#   anthropic — anthropic SDK (required when using Anthropic provider direct,
#               not via OpenRouter)
#
# Add more groups here as needed (voice, mcp, fal, tts-premium, exa, etc.).
# Full list in upstream pyproject.toml [project.optional-dependencies].
#
# Claude Code OAuth bypass (hermes-claude-auth):
#
# We wrap the Hermes binaries to load kristianvast/hermes-claude-auth's
# runtime patch at every invocation. The patch monkey-patches
# agent.anthropic_adapter in memory at import time — it never writes to
# disk, so the read-only Nix store is fine. Upstream's install.sh drops
# `sitecustomize.py` into the venv's site-packages; we can't do that on
# Nix, so instead we prepend the hook directory to PYTHONPATH via the
# wrapper. Python's site.py auto-imports the first `sitecustomize` on
# sys.path at interpreter startup, so the bypass loads transparently.
#
# What the patch does on every OAuth request: forces the Claude Code
# identity into system[0], relocates everything else from `system` into
# the first user message as <system-reminder> blocks, injects a signed
# x-anthropic-billing-header text block, spoofs x-stainless-* headers
# matching Claude Code 2.1.112, namespaces `mcp_*` tools as
# `mcp__hermes__*` (unwrapped on response), and ports several upstream
# 400-fix patches (orphaned tool pairs, haiku effort, Opus 4.6
# temperature, accountUuid → user_id metadata). Without all of this
# Anthropic's server-side validator routes OAuth requests to pay-per-
# token credits instead of the Max/Pro plan.
#
# Hermes reads Claude subscription credentials from
# ~/.claude/.credentials.json, but Claude Code on macOS stores them in
# the Keychain only. The activation hook below tries to mirror the
# Keychain entry into the file on every rebuild — but Keychain Services
# typically refuses access from non-GUI contexts (activation scripts run
# via `sudo -u` from darwin-rebuild, which lacks the loginwindow-unlocked
# Keychain handle even when running as the user). So the auto-mirror
# only succeeds when the daemon happens to have inherited a GUI Keychain
# handle (rare). When it fails, the hook prints a loud warning with the
# exact one-liner to run interactively.
#
# Bumping the bypass when Anthropic rotates fingerprints upstream:
#
#   nix flake lock --update-input hermes-claude-auth
#   sudo darwin-rebuild switch --flake .#m1
{
  mkUserModule,
  pkgs,
  inputs,
  ...
}:
let
  hermesUnwrapped = inputs.hermes-agent.packages.${pkgs.system}.default.override {
    extraDependencyGroups = [
      "messaging"
      "anthropic"
    ];
  };

  # Lay out hermes-claude-auth so the hook is discoverable as
  # `sitecustomize` on sys.path and the bypass module lives in a
  # directory the hook reads via HERMES_PATCHES_DIR.
  claudeAuthFiles = pkgs.runCommand "hermes-claude-auth-files" { } ''
    mkdir -p $out/hook $out/patches
    cp ${inputs.hermes-claude-auth}/sitecustomize_hook.py $out/hook/sitecustomize.py
    cp ${inputs.hermes-claude-auth}/anthropic_billing_bypass.py $out/patches/anthropic_billing_bypass.py
  '';

  # Wrap every hermes binary so:
  #   - PYTHONPATH prepends our sitecustomize.py → Python's site.py
  #     auto-imports it at interpreter startup, before any user code.
  #   - HERMES_PATCHES_DIR points the hook at the bypass module so it
  #     can `import anthropic_billing_bypass` after the venv loads.
  # Scoping these via the wrapper (not home.sessionVariables) keeps
  # PYTHONPATH from leaking into other Python tools in the shell.
  hermes = pkgs.symlinkJoin {
    name = "hermes-agent-with-claude-auth";
    paths = [ hermesUnwrapped ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in $out/bin/*; do
        wrapProgram "$bin" \
          --prefix PYTHONPATH : "${claudeAuthFiles}/hook" \
          --set-default HERMES_PATCHES_DIR "${claudeAuthFiles}/patches"
      done
    '';
  };
in
mkUserModule {
  name = "nalum";

  parts = {
    gateway = import ./gateway.nix { inherit hermes; };
  };

  home =
    { username, ... }:
    let
      nalumDir = "/Users/${username}/nalum";
      credPath = "/Users/${username}/.claude/.credentials.json";
    in
    {
      home = {
        packages = [ hermes ];
        sessionVariables.HERMES_HOME = nalumDir;
        activation.nalumCheck = ''
          if [ ! -d "${nalumDir}" ]; then
            echo ""
            echo "  ⚠ nalum: ${nalumDir} does not exist."
            echo "    Hermes will auto-create it on first run, but for declarative"
            echo "    tracking initialize it as a private git repo first:"
            echo ""
            echo "      mkdir -p ${nalumDir} && cd ${nalumDir} && git init"
            echo ""
          fi

          # The live ~/Library/LaunchAgents/ai.hermes.gateway.plist is owned
          # by nix-darwin's setupLaunchAgents step — leave it alone, the
          # rebuild overwrites it atomically. We only sweep the
          # `.disabled-*` archives that upstream's `hermes gateway install`
          # flow leaves behind when it shuffles old plists aside, since
          # those will never be cleaned by anything else.
          legacy_dir="/Users/${username}/Library/LaunchAgents"
          for legacy in "$legacy_dir"/ai.hermes.gateway.plist.disabled-*; do
            [ -e "$legacy" ] || continue
            rm -f "$legacy"
            echo "  ✓ nalum: removed stale archived launchd plist $legacy"
          done

          # Ensure the log dir exists so launchd can open
          # StandardOutPath/StandardErrorPath on first boot. Hermes
          # creates it on first run too, but launchd may try to open
          # the file before Hermes touches it.
          mkdir -p "${nalumDir}/logs"

          # Try to mirror Claude Code Keychain → ${credPath}. Almost
          # always fails in activation context (no GUI Keychain handle),
          # so the warning branch below is the common path.
          mirrored=0
          if command -v security >/dev/null 2>&1; then
            if cred=$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null); then
              if [ ! -f "${credPath}" ] || [ "$(cat "${credPath}" 2>/dev/null)" != "$cred" ]; then
                mkdir -p "$(dirname "${credPath}")"
                printf '%s' "$cred" > "${credPath}"
                chmod 600 "${credPath}"
                echo "  ✓ nalum: mirrored Claude Code credentials from Keychain → ${credPath}"
              fi
              mirrored=1
            fi
          fi

          # If the file is missing after the mirror attempt, print a loud
          # warning with the exact command to run interactively. Keychain
          # Services typically refuses access from sudo-spawned activation
          # contexts, so this is expected on most rebuilds.
          if [ "$mirrored" -eq 0 ] && [ ! -f "${credPath}" ]; then
            echo ""
            echo "  ⚠ nalum: hermes-claude-auth needs ${credPath} but it's missing."
            echo "    The activation hook can't read the login Keychain (no GUI handle)."
            echo "    Run this once in your interactive shell:"
            echo ""
            echo "      security find-generic-password -s 'Claude Code-credentials' -w \\"
            echo "        > ${credPath} && chmod 600 ${credPath}"
            echo ""
            echo "    Click 'Always Allow' on the Keychain prompt. If no Keychain entry"
            echo "    exists, authenticate Claude Code first: claude auth login --claudeai"
            echo ""
          fi
        '';
      };
    };
}
