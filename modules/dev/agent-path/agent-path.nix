# Agent PATH: ~/.agents/bin goes in front of PATH for everything an agent
# runs, so a script there shadows the real command for agents only. Nalum puts
# it on its own PATH; login shells in agents/* sessions of limi-desktop's mux
# pick it up through ~/.profile. A shim reaches the
# real command by dropping its own directory from PATH (see gh.sh).
{ mkUserModule, ... }:
mkUserModule {
  name = "agent-path";
  home =
    { userCfg, ... }:
    {
      home.file = {
        ".agents/bin/gh" = {
          source = ./gh.sh;
          executable = true;
        };
      }
      // (if userCfg.limi-suite.enable then { ".agents/profile".source = ./profile.sh; } else { });

      # agents/* sessions run `/bin/sh -l`, which reads ~/.profile.
      # That file isn't ours (installers append to it), so only make sure it
      # sources ours; the guard keeps it harmless once the module is off.
      home.activation.agentPathProfile = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          f="$HOME/.profile"
          line='[ -r "$HOME/.agents/profile" ] && . "$HOME/.agents/profile"'
          grep -qxF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
        '';
      };
    };
}
