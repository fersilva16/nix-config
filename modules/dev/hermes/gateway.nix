# hermes gateway — declarative launchd agent for `hermes gateway run`.
#
# Replaces the upstream `hermes gateway install` flow, which writes
# ~/Library/LaunchAgents/ai.hermes.gateway.plist out-of-band and pins
# /nix/store paths inside it that go stale on every rebuild.  Our
# version regenerates atomically with the host config.
#
# We deliberately keep the upstream label `ai.hermes.gateway` so the
# stock `hermes gateway {start,stop,restart,status}` CLI subcommands —
# which derive the label from HERMES_HOME via `get_launchd_plist_path`
# in hermes_cli/gateway.py — talk to OUR agent.  This means a manual
# `hermes gateway install` would overwrite our plist with a stale
# hardcoded copy; the next `darwin-rebuild switch` restores it.
#
# The parent module's activation hook strips the `.disabled-*` archive
# files upstream's installer leaves behind; the live plist itself is
# atomically rewritten by nix-darwin's setupLaunchAgents step.
{
  hermes,
  forPlatform,
  ...
}:
{
  # launchd is darwin-only; systemd port deferred until wanted on linux.
  system = forPlatform {
    linux = _: { };
    darwin =
      { partUsers }:
      let
        # mkUserModule passes partUsers as { username = userCfg; ... }.
        # The gateway is inherently host-scoped (one HERMES_HOME per machine),
        # so only one user may enable it.  Loud fail beats a silent last-wins.
        usernames = builtins.attrNames partUsers;
        username =
          if builtins.length usernames == 1 then
            builtins.head usernames
          else
            throw "hermes.gateway: exactly one user must enable the gateway (got: ${builtins.toJSON usernames})";
        nalumDir = "/Users/${username}/nalum";
      in
      {
        launchd.user.agents.hermes-gateway = {
          serviceConfig = {
            Label = "ai.hermes.gateway";
            ProgramArguments = [
              "${hermes}/bin/hermes"
              "gateway"
              "run"
              "--replace"
            ];
            EnvironmentVariables = {
              HERMES_HOME = nalumDir;
            };
            WorkingDirectory = nalumDir;
            RunAtLoad = true;
            # Restart only on abnormal exit — clean shutdowns (e.g. `hermes
            # gateway stop`) should stay stopped.
            KeepAlive = {
              SuccessfulExit = false;
            };
            StandardOutPath = "${nalumDir}/logs/gateway.log";
            StandardErrorPath = "${nalumDir}/logs/gateway.error.log";
          };
        };
      };
  };
}
