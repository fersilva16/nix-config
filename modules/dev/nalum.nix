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
{
  mkUserModule,
  pkgs,
  inputs,
  ...
}:
mkUserModule {
  name = "nalum";

  home =
    { username, ... }:
    let
      nalumDir = "/Users/${username}/nalum";
    in
    {
      home = {
        packages = [ inputs.hermes-agent.packages.${pkgs.system}.default ];
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
        '';
      };
    };
}
