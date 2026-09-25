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

        A worktree can be a stack of PRs, one worktree per PR. `wts` (a binary,
        works from sh) prints the stack for the current directory, what to do
        next, and the rules. Run it before any branch, rebase, push, or PR work
        in a worktree, and again whenever you are unsure of the stack's state.
        To split work into stacked PRs: `wts add <name>` once per PR, bottom
        first. To check out an existing stacked PR: `wts pull [pr#]`. Never
        create, rebase, or retarget stack branches by hand; `wts help` lists
        the commands.
      '';
    };
}
