# worktree stacked part — stacked PRs via git-stack-cli (commit-as-unit).
#
# Model: a stack is ONE git worktree on ONE branch carrying a line of commits.
# git-stack-cli (`git stack`) groups contiguous commit ranges into PRs, pushes
# each group to its own branch, and chains the PR bases bottom→top. All state
# lives in commit-message trailers (`git-stack-id`) + GitHub — there is no local
# sidecar db and no second VCS, so plain `git` stays the daily driver and every
# git-based tool (tmux, starship, zoxide, opencode) needs zero awareness of it.
#
# The engine is bundled here (the `git-stack` binary + git-revise, its rebase
# helper), mirroring how the old build bundled jujutsu. `wts` wraps it:
# worktree/session lifecycle is plain `git worktree` (reusing wt/wtrm), the
# scriptable subcommands (log, fixup, rebase, check) are thin wrappers, and
# grouping/publish drops into `git stack`'s interactive TUI — it has no headless
# mode. Unknown subcommands fall through to `git stack` as an escape hatch.
#
# Tradeoff vs the old jj engine: conflicts during `wts sync` are plain git
# (stop-and-resolve per layer) — git-stack-cli has none of jj's first-class
# conflict propagation. Everything else (single worktree, commit-as-unit,
# adoptable metadata-less stacks, no second VCS) is the win.
{ pkgs }:
let
  inherit (pkgs) lib;

  # nixpkgs ships git-revise 0.7.0 (GPG-only signing). git-stack-cli rebases via
  # `git revise`, and commits here are signed with SSH (1Password) — unsupported
  # until v0.8.0 (PR #136). Without it the revise step aborts trying to run a
  # missing `gpg`. Override to 0.8.0 so it signs via gpg.format=ssh +
  # gpg.ssh.program (op-ssh-sign), keeping the stack's commits signed.
  git-revise = pkgs.git-revise.overridePythonAttrs (old: {
    version = "0.8.0";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/source/g/git-revise/git_revise-0.8.0.tar.gz";
      hash = "sha256-MjmxgJzWWbM/bzI9O/ylx+Op6y6s4iPPY7NG+RyMgxw=";
    };
    # 0.8.0 switched setup.py → pyproject.toml (hatchling), and its PyPI sdist
    # omits the tests dir, so the upstream pytest checkPhase collects nothing
    # and fails — build it as a pyproject and skip the check.
    format = "pyproject";
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3.pkgs.hatchling ];
    doCheck = false;
  });

  git-stack-cli = pkgs.stdenvNoCC.mkDerivation {
    pname = "git-stack-cli";
    version = "2.11.0";

    src =
      {
        aarch64-darwin = pkgs.fetchurl {
          url = "https://github.com/magus/git-stack-cli/releases/download/2.11.0/git-stack-bun-darwin-arm64.zip";
          hash = "sha256-uvqM/dWRjKsfeZw3MwQ0G3R4bXIEVAdRm4jEU1JwARM=";
        };
      }
      .${pkgs.stdenvNoCC.hostPlatform.system}
        or (throw "git-stack-cli: unsupported system ${pkgs.stdenvNoCC.hostPlatform.system}");

    nativeBuildInputs = [
      pkgs.unzip
      pkgs.perl
    ];
    sourceRoot = ".";

    # The release zip is a single Bun-compiled binary; install it as `git-stack`
    # so it resolves as the `git stack` subcommand.
    #
    # Trunk patch: 2.11.0 reads the trunk from GIT_STACK_CONFIG.branch via
    # yargs `.config()` — but that is wired ONLY into the default ($0) command
    # builder, so every other subcommand (`rebase`, `fixup`, …) ignores it and
    # falls back to the hardcoded origin/master→origin/main. `rebase` also
    # rejects the -b flag. Net effect: `git stack rebase` cannot be pointed at a
    # non-main trunk (verified against this exact binary).
    #
    # Fix the root cause instead of hardcoding a trunk: make rebase's builder
    # apply the env config like $0 does. `.strict(!1)` (already used by the `log`
    # builder) lets the injected `branch` key through yargs strict validation,
    # then `.config(u.env_config||{})` merges it (c9's `u` defaults to {}, so
    # this is safe with no GIT_STACK_CONFIG). The trunk now comes from whatever
    # _wts_gs injects (origin/<_wts_trunk>) — single source of truth, no trunk
    # baked into Nix. Length-preserving (description trimmed to match), so the
    # Bun blob's offsets stay valid (binary still runs + reports 2.11.0); the
    # string lives in the appended JS bundle, outside the signed Mach-O region.
    # The `or die` makes a version bump fail loudly if the pattern moves.
    installPhase = ''
      runHook preInstall
      install -Dm755 git-stack-bun-darwin-arm64 $out/bin/git-stack
      OLD='.command("rebase","Update local branch via rebase with latest changes from origin master branch",(z)=>z)'
      NEW='.command("rebase","Rebase the local branch to latest trunk.",(z)=>z.strict(!1).config(u.env_config||{}))'
      OLD="$OLD" NEW="$NEW" perl -0777 -i -pe 'BEGIN{$o=$ENV{OLD};$n=$ENV{NEW}} (s/\Q$o\E/$n/g)==1 or die "git-stack rebase config patch: expected exactly 1 match (version bump?)\n"' $out/bin/git-stack
      runHook postInstall
    '';

    meta = {
      description = "git-stack-cli — commit-as-unit stacked pull requests for GitHub";
      homepage = "https://github.com/magus/git-stack-cli";
      license = lib.licenses.mit;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "git-stack";
    };
  };
in
{
  home = {
    # git-stack is the engine; git-revise is the in-memory rebase helper it
    # shells out to. gh comes from the git module.
    home.packages = [
      git-stack-cli
      git-revise
    ];

    programs.fish = {
      functions = {
        wts = ''
          set -l sub $argv[1]
          set -e argv[1]

          switch "$sub"
            case ""
              # Bare `wts` → bare `git stack` (group commits → PRs TUI).
              _wts_gs $argv

            case log
              # Show the stack: commits since trunk, grouped into their PRs.
              _wts_gs log $argv

            case push
              # Group commits → PRs, push each group, chain bases bottom→top.
              # Interactive (git stack has no headless mode) — this is where you
              # assign commit ranges to PRs.
              _wts_gs $argv

            case sync
              # Rebase the stack onto the latest trunk via `git stack rebase`
              # (fetches origin + drops already-merged commits). Routed through
              # _wts_gs so GIT_STACK_CONFIG.branch = origin/<trunk> is injected;
              # the binary is patched (see derivation) so rebase now honors it.
              # git-revise (0.8.0) SSH-signs via 1Password; trailers survive.
              _wts_gs rebase $argv

            case fixup
              # Fold staged changes into an earlier commit in the stack — the
              # "commit to a parent PR" flow. `wts log` shows commit numbers.
              _wts_gs fixup $argv

            case commit ci
              # Commits are plain git commits; this is a passthrough for parity.
              git commit $argv

            case new
              _wts_new $argv

            case pr adopt
              _wts_adopt $argv

            case land
              _wts_land $argv

            case rm
              # Plain worktree teardown (worktree + branch + tmux session).
              wtrm $argv

            case sessions
              _wts_pick_session

            case check
              # Non-interactive status table (no TUI, no sync).
              _wts_gs --check $argv

            case help -h --help
              echo "wts — stacked PRs via git-stack-cli (commit-as-unit; git stack + gh)" >&2
              echo "" >&2
              echo "  wts new <name>       fresh stack worktree + session (branch off trunk)" >&2
              echo "  wts pr <pr#> [name]  adopt an existing remote stack into a worktree" >&2
              echo "  wts                  bare git stack (group commits → PRs TUI)" >&2
              echo "  wts log              show the stack (git stack log)" >&2
              echo "  wts commit [-m msg]  plain git commit on the stack branch" >&2
              echo "  wts push             group commits → PRs + push + chain (git stack TUI)" >&2
              echo "  wts fixup <n>        fold staged changes into commit n (fix a parent PR)" >&2
              echo "  wts sync             fetch + rebase the stack onto latest trunk" >&2
              echo "  wts land             merge the bottom PR, then re-sync the rest" >&2
              echo "  wts rm [name]        remove the worktree + branch + session" >&2
              echo "  wts sessions         worktree session picker" >&2
              echo "  wts check            non-interactive status (git stack --check)" >&2
              echo "" >&2
              echo "anything else falls through to git stack, e.g. 'wts rebase', 'wts config'." >&2

            case '*'
              # Passthrough: unrecognised subcommands go straight to git stack
              # (still with the trunk injected).
              _wts_gs $sub $argv
          end
        '';

        # Resolve the repo's trunk (default branch). Prefer an explicit
        # `git config wts.trunk` override (e.g. `prod`); then the local
        # origin/HEAD symref (offline); fall back to gh, then `main`.
        _wts_trunk = ''
          set -l t (git config wts.trunk 2>/dev/null)
          if test -z "$t"
            set t (git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | string replace -r '^origin/' "")
          end
          if test -z "$t"
            set t (gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
          end
          test -z "$t"; and set t main
          echo $t
        '';

        # Run `git stack` with the repo's REAL trunk injected via GIT_STACK_CONFIG,
        # which the binary honors globally across every subcommand (several reject
        # the -b flag, e.g. rebase). git-stack-cli only auto-detects
        # origin/master|main, so this is what makes it work on any default branch
        # (e.g. prod). Signing is left ON — `git revise` (0.8.0 override above)
        # SSH-signs via 1Password. Scoped to the call via `env`; an explicit
        # GIT_STACK_CONFIG override is respected.
        _wts_gs = ''
          if test -n "$GIT_STACK_CONFIG"
            git stack $argv
            return $status
          end
          set -l t (_wts_trunk)
          if test -n "$t"
            env GIT_STACK_CONFIG="{\"branch\":\"origin/$t\"}" git stack $argv
          else
            git stack $argv
          end
        '';

        # Start a fresh stack in its own worktree (named dir + tmux session),
        # branched off the latest trunk. A "stack" is just this branch — commit
        # onto it, then `wts push` to carve the commits into PRs.
        _wts_new = ''
          set -l name $argv[1]
          if test -z "$name"
            echo "wts new: usage: wts new <name>" >&2
            return 1
          end
          set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          if test -z "$main_root"
            echo "wts new: not a git repo" >&2
            return 1
          end
          set -l repo_name (basename $main_root)
          set -l wt_base (dirname $main_root)
          set -l ws_path "$wt_base/$repo_name.worktrees/$name"
          if test -e "$ws_path"
            echo "wts new: '$ws_path' already exists" >&2
            return 1
          end

          git fetch origin 2>/dev/null
          set -l trunk (_wts_trunk)
          git worktree add -b $name "$ws_path" "origin/$trunk"
          or begin
            echo "wts new: git worktree add failed" >&2
            return 1
          end
          direnv allow "$ws_path" 2>/dev/null
          echo "✓ new stack '$name' (on $trunk)"
          _wts_open_session $name "$ws_path"
        '';

        # Adopt an existing remote stacked PR into its own worktree. With no PR
        # number, fzf over open PRs (like wtpr). Walk the selected PR's stack to
        # find its tip, then check the tip branch out into a worktree — the tip
        # carries the whole stack's commits, so `wts push` (git stack) can map
        # them back onto the existing PRs in the TUI (matched by branch name, so
        # no duplicate PRs are created).
        _wts_adopt = ''
          set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          if test -z "$main_root"
            echo "wts pr: not a git repo" >&2
            return 1
          end

          set -l pr (string replace -r '^#' "" -- $argv[1])
          # No PR number: fzf picker over open PRs (ported from wtpr).
          if test -z "$pr"
            set -l selection (gh pr list --limit 50 --json number,title,headRefName,author,isDraft --template '{{range .}}#{{.number}}  {{if .isDraft}}[DRAFT] {{end}}{{.title}}  ({{.headRefName}})  @{{.author.login}}{{"\n"}}{{end}}' 2>/dev/null | fzf --prompt="PR> " --height=40%)
            or return 1
            set pr (string match -r '^#(\d+)' -- $selection)[2]
          end
          set pr (string replace -r '^#' "" -- $pr)
          if test -z "$pr"; or string match -qr '[^0-9]' -- "$pr"
            echo "wts pr: invalid PR number" >&2
            return 1
          end

          set -l rows (gh pr list --state open --limit 200 --json number,headRefName,baseRefName --jq '.[] | "\(.number)\t\(.headRefName)\t\(.baseRefName)"' 2>/dev/null)
          or begin
            echo "wts pr: gh pr list failed" >&2
            return 1
          end
          set -l numbers
          set -l heads
          set -l bases
          for r in $rows
            set -l f (string split \t -- $r)
            set -a numbers $f[1]
            set -a heads $f[2]
            set -a bases $f[3]
          end
          set -l si (contains -i -- $pr $numbers)
          if test -z "$si"
            echo "wts pr: PR #$pr not found among open PRs" >&2
            return 1
          end
          # Collect the connected stack of head branches: fixpoint over the
          # head<->base edges (walk down to trunk and up to the tip).
          set -l stack $heads[$si]
          set -l changed 1
          while test $changed -eq 1
            set changed 0
            for i in (seq (count $heads))
              if contains -- $heads[$i] $stack; and contains -- $bases[$i] $heads; and not contains -- $bases[$i] $stack
                set -a stack $bases[$i]
                set changed 1
              end
              if contains -- $bases[$i] $stack; and not contains -- $heads[$i] $stack
                set -a stack $heads[$i]
                set changed 1
              end
            end
          end
          # Top of the stack = the head that is not used as anyone's base.
          set -l usedbases
          for i in (seq (count $heads))
            if contains -- $heads[$i] $stack
              set -a usedbases $bases[$i]
            end
          end
          set -l top
          for h in $stack
            if not contains -- $h $usedbases
              set top $h
            end
          end
          if test -z "$top"
            echo "wts pr: could not determine stack tip" >&2
            return 1
          end

          # Worktree name: arg, else prompt with the PR's head branch
          # (sanitized) as default — short names avoid huge tmux session labels.
          set -l name $argv[2]
          if test -z "$name"
            set -l default_name (string replace -a '/' '-' -- $heads[$si])
            read -P "wts pr: worktree name [$default_name]: " name
            or return 1
            test -z "$name"; and set name $default_name
          end
          set -l repo_name (basename $main_root)
          set -l wt_base (dirname $main_root)
          set -l ws_path "$wt_base/$repo_name.worktrees/$name"
          if test -e "$ws_path"
            echo "wts pr: '$ws_path' already exists" >&2
            return 1
          end

          # Fetch + check out the tip branch (carries the whole stack's commits).
          git fetch origin "+refs/heads/$top:refs/remotes/origin/$top" 2>/dev/null
          or begin
            echo "wts pr: failed to fetch '$top'" >&2
            return 1
          end
          if git show-ref --verify --quiet "refs/heads/$top"
            git worktree add "$ws_path" "$top"
          else
            git worktree add --track -b "$top" "$ws_path" "origin/$top"
          end
          or begin
            echo "wts pr: git worktree add failed" >&2
            return 1
          end
          direnv allow "$ws_path" 2>/dev/null
          echo "✓ adopted stack tip '$top' ("(count $stack)" branch(es)) into '$name'"
          echo "  run 'wts push' to map commits → these PRs in the git stack TUI"
          _wts_open_session $name "$ws_path"
        '';

        # Land the bottom PR (stacks merge bottom-up). The bottom group is the
        # git-stack-id of the oldest commit above trunk; merge its PR (deleting
        # the branch so GitHub auto-retargets the child onto trunk), then fetch +
        # rebase the remainder. Re-sync the rest with `wts push`.
        _wts_land = ''
          set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
          if test -z "$main_root"
            echo "wts land: not a git repo" >&2
            return 1
          end
          set -l trunk (_wts_trunk)
          set -l bottom (git log "origin/$trunk..HEAD" --reverse --format='%(trailers:key=git-stack-id,valueonly)' 2>/dev/null | string match -r '.+' | head -1)
          if test -z "$bottom"
            echo "wts land: no git-stack metadata in the stack — run 'wts push' first" >&2
            return 1
          end
          set -l prnum (gh pr view "$bottom" --json number --jq .number 2>/dev/null)
          if test -z "$prnum"
            echo "wts land: bottom group '$bottom' has no PR — run 'wts push' first" >&2
            return 1
          end
          echo "Landing bottom of stack: $bottom (PR #$prnum)"
          read -P "Merge PR #$prnum into $trunk? [y/N] " ok
          string match -qi y -- "$ok"; or return 1
          gh pr merge $prnum -s --delete-branch
          or begin
            echo "wts land: merge failed" >&2
            return 1
          end
          git fetch origin 2>/dev/null
          git rebase "origin/$trunk" 2>/dev/null
          echo "✓ landed PR #$prnum — run 'wts push' to re-sync the remainder"
        '';

        # Open (or switch to) a tmux session for a worktree dir, mirroring `wt`.
        _wts_open_session = ''
          set -l name $argv[1]
          set -l path $argv[2]
          direnv allow "$path" 2>/dev/null
          if not set -q TMUX
            echo "  not in tmux — cd $path"
            return 0
          end
          set -l parent (command tmux display-message -p '#{session_name}' | string split -m 1 '/')[1]
          set -l session "$parent/$name"
          set -l created 0
          if not command tmux has-session -t "=$session" 2>/dev/null
            command tmux new-session -d -s "$session" -c "$path"
            set created 1
          end
          # Run the repo's worktree setup script on first creation (mirrors wt/wtpr).
          if test $created -eq 1
            set -l setup_file (dirname $path)/.setup
            if test -f "$setup_file"
              command tmux send-keys -t "=$session" "sh '$setup_file'" Enter
            end
          end
          command tmux switch-client -t "=$session"
        '';

        # Plain tmux session picker (a stack lives inside one session, so there's
        # no cross-session topology to render — use 'wts log' for the stack view).
        _wts_pick_session = ''
          if not set -q TMUX
            echo "wts sessions: requires tmux" >&2
            return 1
          end
          set -l choice (command tmux list-sessions -F '#{session_name}' | string match -v pocket | fzf --prompt="session> " --height=40%)
          or return 1
          command tmux switch-client -t "=$choice"
        '';
      };

      shellInit = ''
        # Completion for wts: subcommands.
        complete -f -c wts -n "__fish_use_subcommand" -a "new pr log commit push fixup sync land rm sessions check help"
      '';
    };
  };
}
