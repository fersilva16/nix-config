# worktree stack part — stacked PRs as worktrees, operated by agents.
#
# A stack is a normal `wt` worktree (the root, never a PR) plus one worktree
# per PR under <repo>.worktrees/.stacks/<root>/. Order lives in git itself:
# each layer's upstream is the layer below, the root's upstream is the top.
# `wts` is the only interface, a real binary so agents can call it from sh; it
# re-derives the stack on every call and prints the rules with it, so an agent
# deep in a long session never has to remember them. See wts.sh.
{
  pkgs,
  wt-claim,
  wt-create,
  wt-enter,
  wt-pool-fill,
}:
let
  wts = pkgs.writeShellApplication {
    name = "wts";
    runtimeInputs = [
      pkgs.git
      pkgs.gh
      pkgs.jq
      wt-claim
      wt-create
      wt-enter
      wt-pool-fill
    ];
    text = builtins.readFile ./wts.sh;
  };
in
{
  home =
    { lib, userCfg, ... }:
    {
      home.packages = [ wts ];

      # `types.lines`, so this concatenates onto opencode's global AGENTS.md.
      xdg.configFile."opencode/AGENTS.md".text = lib.mkIf userCfg.opencode.enable ''

        ## Worktree stacks

        Stacked PRs are one worktree per PR, run through `wts` (works from sh).
        Run `wts` before any branch, rebase, push or PR work in a worktree: it
        prints the stack, the rules, and the commands to run under `next:`.
        Those are pre-approved: run them without asking.
      '';
    };
}
