# omo agent part: the `agent` CLI, which talks to omo sessions over omo's
# shared RPC host, plus the orchestrator that uses it to run agents in `wt`
# worktrees. The CLI only reaches TUIs on that host, but a TUI on it loses
# ui's pickers (/resume and friends run host-side, where there is no real
# tui to draw on), so only the agents `agent spawn` starts join it; your own
# TUIs stay standalone (experimental.sharedHost off, the upstream default).
{ pkgs, lib }:
let
  agent = pkgs.writeShellApplication {
    name = "agent";
    runtimeInputs = [
      pkgs.bun
      pkgs.gh
      pkgs.git
      pkgs.tmux
    ];
    # AGENT_CLI: `spawn --needs` types this same build into the new pane.
    text = ''AGENT_CLI="$0" exec bun ${./agent.ts} "$@"'';
  };
in
{
  home =
    { userCfg, ... }:
    {
      home = {
        packages = [ agent ];

        # `/agent` switches between OmO and the orchestrator; spawn needs `wt`
        # and every agent lives in a tmux session.
        file = lib.mkIf (userCfg.tmux.enable && userCfg.worktree.enable) {
          ".omo/agent/extensions/agents".source = ../agents;
        };
      };
    };
}
