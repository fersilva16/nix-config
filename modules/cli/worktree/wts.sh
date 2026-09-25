# shellcheck shell=bash
# wts — stacked PRs as worktrees, run by agents. Nothing is stored beside git;
# every call derives the stack from two facts:
#   members  worktrees under <repo>.worktrees/.stacks/<root>/
#   order    each layer's upstream is the layer below (bottom: origin/<trunk>),
#            and the root's upstream is the top layer
# so plain `git status` in any member already reports ahead/behind its parent.

die() {
  printf 'wts: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
wts — stacked PRs, one worktree per PR. Run from the stack root or any layer.

  wts                      the stack, bottom → top: each layer's parent, commits,
                           origin and PR state, worktree and agent; what to do next
  wts add <name> [branch] [--after <layer>|trunk]
                           new layer on top (or right above <layer>); the first
                           add turns the current worktree into the stack root
  wts rm <name> [--force]  remove a layer; its commits fold into the one above,
                           or drop out if its PR already merged
  wts sync [--main] [--force]
                           fetch; move layers that are only older copies of
                           origin to origin; rebase each layer onto the one below;
                           move the root onto the top. --main also moves the
                           bottom onto the latest trunk
  wts pull [pr#] [--root <name>] [<layer name>...]
                           check out an open PR's whole stack, one layer per PR,
                           root at its top PR. Without names it lists the PRs;
                           rerun with one short name per PR, bottom → top. Run in
                           a plain wt worktree, that worktree becomes the root
                           and pr# defaults to its branch's PR; with --root, or
                           anywhere else, root is a new worktree (pr<pr#>).

@them's layers (pulled from others' PRs): sync needs --force and a plain git
push fails. Both need the user's go-ahead.
EOF
}

rules() {
  cat <<EOF
rules:
  - a layer is one PR on the layer below; it has no PR until the user asks
  - root is never pushed: commit its work into layers, then wts sync
  - run next: without asking; ask before closing a PR, dropping an unmerged
    layer, or touching an @them's layer
  - restack only with wts sync; never git push -u in a layer
  - leave root's uncommitted files and busy agents' layers alone
  - PR, CI and review state is context, not a to-do
EOF
}

repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repo"
  main_root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
  wd="$(dirname "$main_root")/$(basename "$main_root").worktrees"
  trunk=$(git config wts.trunk || true)
  if [ -z "$trunk" ]; then
    trunk=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
    trunk=${trunk#origin/}
  fi
  : "${trunk:=main}"
}

ctx() {
  repo
  here=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repo"
  case "$here" in
  "$wd"/.stacks/*/*) name=${here#"$wd"/.stacks/} name=${name%%/*} ;;
  "$wd"/*) name=${here#"$wd"/} ;;
  *) die "not in a wt worktree (stacks live under $wd; the main checkout can't be one)" ;;
  esac
  case "$name" in */* | .*) die "not a stack root or layer: $here" ;; esac
  root="$wd/$name"
  sdir="$wd/.stacks/$name"
  root_b=$(wt_branch "$root") || die "root $root is not on a branch"
}

# A worktree's branch, even mid-rebase (HEAD is detached then, and git keeps
# the branch name in the rebase state instead).
wt_branch() {
  local b g
  b=$(git -C "$1" branch --show-current 2>/dev/null || true)
  for g in rebase-merge rebase-apply; do
    [ -z "$b" ] || break
    g=$(git -C "$1" rev-parse --path-format=absolute --git-path "$g/head-name")
    [ ! -f "$g" ] || b=$(sed 's|^refs/heads/||' "$g")
  done
  [ -n "$b" ] && echo "$b"
}

# Sets order (layer branches, bottom → top), lpath[branch], up[branch], root_up.
load() {
  declare -gA up=() lpath=()
  local d b u cur="" next all=()
  root_up=$(git rev-parse --abbrev-ref "$root_b@{upstream}" 2>/dev/null || true)
  for d in "$sdir"/*/; do
    d=${d%/}
    [ -e "$d/.git" ] || continue
    b=$(wt_branch "$d") || continue
    all+=("$b")
    lpath[$b]=$d
    up[$b]=$(git rev-parse --abbrev-ref "$b@{upstream}" 2>/dev/null || true)
  done
  order=()
  ((${#all[@]})) || return 0
  for b in "${all[@]}"; do
    u=${up[$b]}
    [ -n "$u" ] && [ -n "${lpath[$u]+x}" ] && continue
    [ -z "$cur" ] || die "layers $cur and $b both sit at the bottom — point one at the other: git branch --set-upstream-to=<layer below> <branch>"
    cur=$b
  done
  [ -n "$cur" ] || die "the layers' upstreams form a loop — fix with git branch --set-upstream-to"
  while [ -n "$cur" ]; do
    order+=("$cur")
    next=""
    for b in "${all[@]}"; do
      [ "${up[$b]}" = "$cur" ] || continue
      [ -z "$next" ] || die "layers $next and $b both sit on $cur — a stack is one line: git branch --set-upstream-to=<layer below> <branch>"
      next=$b
    done
    cur=$next
  done
  ((${#order[@]} == ${#all[@]})) || die "some layers aren't chained to the bottom — check each layer's upstream (git -C <layer> status)"
}

lname() { basename "${lpath[$1]}"; }
parent() { if (($1)); then echo "${order[$1 - 1]}"; else echo "origin/$trunk"; fi; }
base_of() { if (($1)); then echo "${order[$1 - 1]}"; else echo "$trunk"; fi; }
find_layer() {
  local i
  for i in "${!order[@]}"; do
    [ "$(lname "${order[$i]}")" = "$1" ] && echo "$i" && return 0
  done
  return 1
}
in_rebase() {
  local g
  for g in rebase-merge rebase-apply; do
    [ -d "$(git -C "$1" rev-parse --path-format=absolute --git-path "$g")" ] && return 0
  done
  return 1
}
dirty() { [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }
# The session for worktree $1: the one started there, else one under session
# $2 whose shell sits there now. A moved worktree (git worktree move) keeps its
# session, still carrying the old start path, and the shell moves with it.
# agents/* sessions are agents' scratch space, never a worktree's own.
sess_at() {
  local sp sn pp alt=""
  command -v tmux >/dev/null || return 0
  while IFS=$'\t' read -r sp sn pp; do
    [[ "$sn" != agents/* ]] || continue
    if [ "$sp" = "$1" ]; then
      echo "$sn"
      return 0
    fi
    [[ -z "${2:-}" || "$sn" != "$2"/* || "$pp" != "$1" ]] || alt=$sn
  done < <(tmux list-sessions -F "#{session_path}	#{session_name}	#{pane_current_path}" 2>/dev/null)
  [ -z "$alt" ] || echo "$alt"
}
# The session this repo's worktrees hang under ("telepatia" for
# telepatia/programas): whatever an existing worktree session uses, else the
# session on the main checkout, else the caller's — the same thing `wt` uses.
parent_session() {
  local sp sn
  command -v tmux >/dev/null || return 0
  while IFS=$'\t' read -r sp sn; do
    [[ "$sp" == "$wd"/* && "$sn" == */* && "$sn" != agents/* ]] || continue
    echo "${sn%%/*}"
    return 0
  done < <(tmux list-sessions -F "#{session_path}	#{session_name}" 2>/dev/null)
  sn=$(sess_at "$main_root")
  [ -n "$sn" ] || sn=$(tmux display-message -p '#S' 2>/dev/null || true)
  echo "${sn%%/*}"
}
# The root's tmux session: the one started there, else `wt`'s naming
# convention (<parent>/<name>). A worktree renamed with wtmv keeps its
# session's original start path, and tmux never updates it.
root_sess() {
  local s
  s=$(sess_at "$root")
  if [ -z "$s" ]; then
    s="$(parent_session)/$name"
    tmux has-session -t "=$s" 2>/dev/null || s=""
  fi
  echo "$s"
}

# Detached session <root session>/<layer>, unless one exists. No .setup here:
# layers are for committing and restacking, and a dozen parallel `make setup`s
# is minutes of CPU nobody asked for. Root has one.
layer_sess() {
  local s="$1/$2" b
  [ -n "$1" ] || return 0
  ! tmux has-session -t "=$s" 2>/dev/null || return 0
  b=$(wt_branch "$3") || return 0
  tmux new-session -d -s "$s" -c "$3" "'$(command -v wt-enter)' '$main_root' '$3' '$b' '$b' '$s' ''"
}

# Author of a layer pulled from someone else's PR (set by `wts pull`), else "".
valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,15}$ ]] && [ "$1" != trunk ]; }
owner() { git config "branch.$1.wtsAuthor" || true; }
guard() {
  local a
  a=$(owner "$1")
  [ -z "$a" ] || die "$(lname "$1") is @$a's PR: $2 would rewrite their branch. Ask the user first; then wts $2 --force"
}
# One fetch per wts call: status, sync, rm and pull all want fresh origin refs.
fetched=0
fetch_origin() {
  ((fetched)) || git fetch -q --prune origin || return 1
  fetched=1
}

# Commits on local branch $1 that origin/$1 never had: not in its fetch
# reflog, nor anywhere the local branch was set from origin (a clone leaves no
# reflog for remote refs, so both are needed). Empty = the local branch is only
# an older copy of origin's.
unseen() {
  local seen
  seen=$({
    git reflog show --format=%H "refs/remotes/origin/$1"
    git reflog show --format='%H %gs' "refs/heads/$1" | sed -nE \
      's/^([0-9a-f]+) (branch: Created from (refs\/remotes\/)?origin\/|reset: moving to origin\/|wts pull: match origin).*/\1/p'
  } 2>/dev/null || true)
  # shellcheck disable=SC2086 # one sha per word
  git rev-list --ignore-missing "$1" --not "origin/$1" $seen
}

# ...minus those with a rebased copy on origin/$1: real unpushed work.
unpushed() {
  local left
  left=$(unseen "$1")
  [ -n "$left" ] || return 0
  git cherry "origin/$1" "$1" | sed -n 's/^+ //p' | grep -Fx -f <(printf '%s\n' "$left") || true
}

# Every layer's latest PR (an open one first), one line per layer:
# index, number, state, draft, base, review, CI rollup, mergeable; US-separated
# so empty fields survive `read`. One GraphQL call for the whole stack.
pr_query() {
  local i vars="" sel="" args=()
  for i in "${!order[@]}"; do
    vars+=", \$h$i: String!"
    sel+=" b$i: pullRequests(headRefName: \$h$i, first: 5, orderBy: {field: CREATED_AT, direction: DESC}) { nodes { ...p } }"
    args+=(-f "h$i=${order[$i]}")
  done
  # shellcheck disable=SC2016 # $i/$p are jq variables
  cd "$root" && gh api graphql -F owner='{owner}' -F name='{repo}' "${args[@]}" \
    -f query="query(\$owner: String!, \$name: String!$vars) { repository(owner: \$owner, name: \$name) {$sel } }
fragment p on PullRequest { number state isDraft baseRefName reviewDecision mergeable
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }" \
    --jq '.data.repository | to_entries[] | (.key | ltrimstr("b")) as $i
      | ((.value.nodes | map(select(.state == "OPEN")) | first) // .value.nodes[0]) as $p
      | select($p != null)
      | [$i, $p.number, $p.state, $p.isDraft, $p.baseRefName, $p.reviewDecision,
         $p.commits.nodes[0].commit.statusCheckRollup.state, $p.mergeable]
      | map(if . == null then "" else tostring end) | join("\u001f")'
}

# pr_query's lines on stdin → pr_n/pr_s/pr_d/pr_b/pr_r/pr_c/pr_m[branch].
load_prs() {
  declare -gA pr_n=() pr_s=() pr_d=() pr_b=() pr_r=() pr_c=() pr_m=()
  local i n s d bs r c m b
  while IFS=$'\x1f' read -r i n s d bs r c m; do
    [ -n "$i" ] || continue
    b=${order[$i]}
    pr_n[$b]=$n pr_s[$b]=$s pr_d[$b]=$d pr_b[$b]=$bs pr_r[$b]=$r pr_c[$b]=$c pr_m[$b]=$m
  done
}

# agent[tmux session] = what its opencode is doing; have_agents=0 without the
# opencode manager, in which case nothing is claimed either way.
load_agents() {
  declare -gA agent=()
  have_agents=0
  command -v tmux-opencode-manager >/dev/null || return 0
  have_agents=1
  local s st
  while IFS=$'\t' read -r s st; do
    [ -n "$s" ] || continue
    if [ "$st" = generating ]; then
      agent[$s]=busy
    elif [ -z "${agent[$s]:-}" ]; then
      agent[$s]=idle
    fi
  done < <(tmux-opencode-manager sessions 2>/dev/null | jq -r '.[] | "\(.session)\t\(.status)"' 2>/dev/null || true)
  while IFS=$'\t' read -r s st; do
    case "$st" in permission | question | error) agent[$s]="waiting on the user ($st)" ;; esac
  done < <(tmux-opencode-manager notify list 2>/dev/null | jq -r '.[] | "\(.session)\t\(.event)"' 2>/dev/null || true)
}
agent_of() {
  local a
  if [ -z "$1" ]; then
    echo "no tmux session"
    return 0
  fi
  ((have_agents)) || return 0
  a=${agent[$1]:-}
  if [ -n "$a" ]; then a="agent $a"; else a="no agent"; fi
  [ "$1" != "$me_s" ] || a+=" (you)"
  echo "$a"
}

plural() { if [ "$1" = 1 ]; then echo "1 $2"; else echo "$1 ${2}s"; fi; }
joined() {
  local out="" x
  for x; do [ -z "$x" ] || out+="${out:+ · }$x"; done
  echo "$out"
}

status() {
  load
  if ((${#order[@]} == 0)); then
    echo "$name is not a stack yet."
    echo "  split this work into PRs: wts add <name> once per PR, bottom first"
    echo "  check out the stacked PR this branch is part of: wts pull"
    return 0
  fi
  local tmp ghpid gh_ok=0 fetch_ok=0 i b l p pn lp own f behind ahead lo ro d c s rs top rsync=0 pend=0 x
  local made=() facts=() nx=() fix=() landed=() closed=() pickup=() restack=() pushes=() retarget=() ask=()
  load_prs </dev/null
  tmp=$(mktemp)
  (pr_query) >"$tmp" 2>/dev/null &
  ghpid=$!
  if fetch_origin; then fetch_ok=1; fi
  if wait "$ghpid"; then
    gh_ok=1
    load_prs <"$tmp"
  fi
  rm -f "$tmp"
  load_agents
  me_s=$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null || true)
  rs=$(root_sess)
  made=()
  for b in "${order[@]}"; do
    if [ -n "$rs" ] && [ -z "$(sess_at "${lpath[$b]}" "$rs")" ]; then
      layer_sess "$rs" "$(lname "$b")" "${lpath[$b]}"
      made+=("$rs/$(lname "$b")")
    fi
  done

  echo "stack $name: $(plural ${#order[@]} PR) on $trunk, bottom → top"
  echo "  worktrees  root $root, layers $sdir/<layer>"
  [ -z "$rs" ] || echo "  sessions   root $rs, layers $rs/<layer>"
  ((${#made[@]} == 0)) || echo "  opened missing sessions: ${made[*]}"
  ((fetch_ok)) || echo "  git fetch failed: origin state is from the last fetch"
  ((gh_ok)) || echo "  gh unavailable: PR state unknown"
  for i in "${!order[@]}"; do
    b=${order[$i]} l=$(lname "$b") p=$(parent "$i") own=$(owner "$b") facts=()
    lp=${lpath[$b]}
    if ((i)); then pn=$(lname "$p"); else pn=$trunk; fi

    read -r behind ahead < <(git rev-list --left-right --count "$p...$b")
    f="on $pn: $(plural "$ahead" commit)"
    if ((behind && i)); then
      f+=", missing $(plural "$behind" commit) of $pn ↻"
      if [ -n "$own" ]; then
        ask+=("$l is @$own's and not on the latest $pn: ask them to restack, or with the user's go-ahead: wts sync --force")
      else
        restack+=("$l")
      fi
    elif ((behind)); then
      f+=", $behind behind $trunk"
    fi
    facts+=("$f")

    if ! git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
      if [ "${pr_s[$b]:-}" = MERGED ]; then
        facts+=("deleted on origin")
      else
        facts+=("not on origin yet")
        if [ -z "$own" ]; then pushes+=("$b"); fi
      fi
    else
      read -r lo ro < <(git rev-list --left-right --count "$b...origin/$b")
      if ((lo == 0 && ro == 0)); then
        facts+=("same as origin")
      elif ((lo == 0)); then
        facts+=("origin has $(plural "$ro" "newer commit")")
        pickup+=("$l")
      elif [ -z "$(unseen "$b")" ]; then
        facts+=("origin was rewritten since (local is an old copy)")
        pickup+=("$l")
      else
        if ((ro == 0)); then f="$(plural "$lo" "unpushed commit")"; else f="rewritten here, not pushed yet"; fi
        facts+=("$f")
        if [ -z "$own" ]; then
          pushes+=("$b")
        else
          ask+=("$l has commits @$own's branch lacks: with the user's go-ahead: git push --force-with-lease origin $b")
        fi
      fi
    fi

    if ((gh_ok)) && [ -z "${pr_n[$b]:-}" ]; then
      facts+=("no PR")
    elif ((gh_ok)); then
      f="PR #${pr_n[$b]}"
      case "${pr_s[$b]}" in
      MERGED)
        f+=" merged"
        landed+=("wts rm $l (PR #${pr_n[$b]} merged)")
        ;;
      CLOSED)
        f+=" closed"
        closed+=("$l's PR #${pr_n[$b]} closed unmerged: ask the user whether to wts rm $l")
        ;;
      *)
        if [ "${pr_d[$b]}" = true ]; then f+=" draft"; else f+=" open"; fi
        if [ "${pr_b[$b]}" != "$(base_of "$i")" ]; then
          f+=", based on ${pr_b[$b]} (should be $(base_of "$i"))"
          if [ -z "$own" ]; then
            retarget+=("gh pr edit ${pr_n[$b]} --base $(base_of "$i")")
          else
            ask+=("$l's PR is based on ${pr_b[$b]}, not $(base_of "$i"): with the user's go-ahead: gh pr edit ${pr_n[$b]} --base $(base_of "$i")")
          fi
        fi
        case "${pr_c[$b]}" in
        SUCCESS) f+=", CI passing" ;;
        FAILURE | ERROR) f+=", CI failing" ;;
        PENDING | EXPECTED) f+=", CI running" ;;
        esac
        case "${pr_r[$b]}" in
        APPROVED) f+=", approved" ;;
        CHANGES_REQUESTED) f+=", changes requested" ;;
        REVIEW_REQUIRED) f+=", review required" ;;
        esac
        [ "${pr_m[$b]}" != CONFLICTING ] || f+=", conflicts with its base on GitHub"
        ;;
      esac
      facts+=("$f")
    fi

    d=$(git -C "$lp" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    ((d == 0)) || facts+=("$(plural "$d" "uncommitted file")")
    if in_rebase "$lp"; then
      c=$(git -C "$lp" diff --name-only --diff-filter=U | tr '\n' ' ')
      facts+=("MID-REBASE, conflicts: ${c% }")
      fix+=("resolve conflicts, git -C $lp rebase --continue, wts sync")
    fi
    facts+=("$(agent_of "$(sess_at "$lp" "$rs")")")

    f=""
    [ -z "$own" ] || f="@$own's PR"
    printf '%3d %-16s %s\n' $((i + 1)) "$l" "$(joined "$b" "$f" "last commit $(git log -1 --format=%cr "$b")")"
    printf '      %s\n' "$(joined "${facts[@]}")"
  done

  top=${order[-1]} facts=()
  if [ "$(git rev-parse "$top")" = "$(git rev-parse "$root_b")" ]; then
    f="= top"
  elif git diff --quiet "$top" "$root_b"; then
    f="same files as the top layer, older history"
    rsync=1
  else
    read -r behind ahead < <(git rev-list --left-right --count "$top...$root_b")
    pend=$ahead f=""
    ((ahead == 0)) || f="$(plural "$ahead" commit) not in a layer yet"
    if ((behind)); then
      f+="${f:+, }missing $(plural "$behind" commit) of the top layer"
      rsync=1
    fi
  fi
  [ "$root_up" = "$top" ] || rsync=1
  facts+=("on $(lname "$top"): $f")
  d=$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ((d == 0)) || facts+=("$(plural "$d" "uncommitted file") (the user's)")
  in_rebase "$root" && facts+=("MID-REBASE")
  facts+=("$(agent_of "$rs")")
  printf '%3s %-16s %s\n' "" root "$(joined "$root_b" "never pushed")"
  printf '      %s\n' "$(joined "${facts[@]}")"
  if ((pend)); then
    git log -5 --format='        %h %s' "$top..$root_b"
    ((pend <= 5)) || echo "        … and $((pend - 5)) more"
  fi

  nx=(${fix[@]+"${fix[@]}"} ${landed[@]+"${landed[@]}"})
  f=""
  ((${#pickup[@]} == 0)) || f="picks up newer pushes to ${pickup[*]}"
  ((rsync == 0)) || restack+=(root)
  ((${#restack[@]} == 0)) || f+="${f:+; }restacks ${restack[*]}"
  [ -z "$f" ] || nx+=("wts sync ($f)")
  ((pend == 0)) || nx+=("root has $(plural "$pend" commit) not in a layer: commit each into its layer (git -C <layer>), then wts sync")
  # Refs are shared, so one push from any worktree covers every layer. Bases
  # after pushes: GitHub only takes a base branch it already has.
  ((${#pushes[@]} == 0)) || nx+=("git push --force-with-lease origin ${pushes[*]}")
  nx+=(${retarget[@]+"${retarget[@]}"} ${ask[@]+"${ask[@]}"} ${closed[@]+"${closed[@]}"})
  if ((${#nx[@]})); then
    echo "next:"
    for x in "${nx[@]}"; do echo "  - $x"; done
  fi
  rules
}

add() {
  add_layer "$@"
  pool_fill
  status
}

# Restock the wt pool and refresh refs/remotes, detached (see wt-pool-fill).
pool_fill() { tmux run-shell -b "'$(command -v wt-pool-fill)' '$main_root'" 2>/dev/null || true; }

add_layer() {
  local l="" b="" after="" i p child start lp
  while (($#)); do
    case "$1" in
    --after)
      after=${2:-}
      [ -n "$after" ] || die "--after needs a layer name or 'trunk'"
      shift 2
      ;;
    --after=*) after=${1#--after=} && shift ;;
    -*) die "unknown flag $1" ;;
    *)
      if [ -z "$l" ]; then l=$1; elif [ -z "$b" ]; then b=$1; else die "too many arguments"; fi
      shift
      ;;
    esac
  done
  [ -n "$l" ] || die "usage: wts add <name> [branch] [--after <layer>|trunk]"
  valid_name "$l" || die "layer names are short: lowercase letters, digits and '-', at most 16 chars, not 'trunk' (got '$l')"
  [ "$root_b" != "$trunk" ] || die "root is on $trunk; a stack root needs its own branch"
  git rev-parse -q --verify "origin/$trunk" >/dev/null || die "no origin/$trunk — run git fetch origin"
  load
  lp="$sdir/$l"
  [ ! -e "$lp" ] || die "layer $l already exists"

  # p = the new layer's parent ("" = trunk); child = whoever sits on p today.
  if [ "$after" = trunk ] || { [ -z "$after" ] && ((${#order[@]} == 0)); }; then
    p=""
    child=${order[0]:-$root_b}
  elif [ -z "$after" ]; then
    p=${order[-1]} child=$root_b
  else
    i=$(find_layer "$after") || die "no layer '$after'"
    p=${order[$i]} child=${order[$i + 1]:-$root_b}
  fi
  # At the bottom, start where the stack already forks from trunk, so the
  # root and top stay comparable until a `wts sync --main` moves everyone.
  if [ -n "$p" ]; then start=$p; else start=$(git merge-base "$child" "origin/$trunk"); fi
  [ -n "$b" ] || b="$(git config --default "" wt.prefix)$name-$l"

  mkdir -p "$sdir"
  wt-claim "$main_root" "$lp" "$b" "$start" ||
    wt-create "$main_root" "$lp" "$b" "$start" ||
    die "could not create $lp (log: $sdir/.$l.log)"
  git branch -q --set-upstream-to="${p:-origin/$trunk}" "$b"
  git config "branch.$b.pushRemote" origin
  git branch -q --set-upstream-to="$b" "$child"

  layer_sess "$(root_sess)" "$l" "$lp"
  echo "added layer $l ($b) at $lp"
}

rm_layer() {
  local l="" force=0 i b lp p child tip pr="" merged=0 rc=0 s
  for a in "$@"; do
    case "$a" in
    -f | --force) force=1 ;;
    -*) die "unknown flag $a" ;;
    *) l=$a ;;
    esac
  done
  [ -n "$l" ] || die "usage: wts rm <name> [--force]"
  load
  i=$(find_layer "$l") || die "no layer '$l'"
  b=${order[$i]} lp=${lpath[$b]} p=$(parent "$i") child=${order[$i + 1]:-$root_b}
  ((force)) || ! dirty "$lp" || die "$l has uncommitted changes: commit or move them, or wts rm $l --force"
  tip=$(git rev-parse "$b")
  pr=$(cd "$root" && gh pr list --head "$b" --state all --json number,state \
    --jq '.[0] // empty | "\(.number) \(.state)"' 2>/dev/null || true)
  [ "${pr#* }" = MERGED ] && merged=1

  git branch -q --set-upstream-to="$p" "$child"
  # Merged: its commits are already in the parent (trunk, after a fetch), so
  # drop them from the child. Unmerged: the child keeps them — a fold. A child
  # that's someone else's PR is theirs to restack; wts sync picks that up.
  if ((merged)) && [ "$child" != "$root_b" ] && [ -n "$(owner "$child")" ]; then
    echo "$(lname "$child") (@$(owner "$child")'s) still carries $l's commits until they restack it; wts sync picks that up"
  elif ((merged)) && [ "$child" != "$root_b" ]; then
    ((i)) || fetch_origin || die "git fetch origin failed"
    git -C "${lpath[$child]}" rebase -q --autostash --onto "$p" "$tip" || rc=1
  fi

  s=$(sess_at "$lp" "$(root_sess)")
  [ -z "$s" ] || tmux kill-session -t "=$s" 2>/dev/null || true
  git worktree remove --force "$lp" 2>/dev/null || true
  rm -rf "$lp" "$sdir/.$l.log"
  git worktree prune
  git branch -q -D "$b"
  rmdir "$sdir" 2>/dev/null || true
  echo "removed layer $l ($b)"
  if [ -n "$pr" ] && ((!merged)); then
    echo "PR #${pr%% *} for $b is ${pr#* }; its changes now live in the layer above — close it if it's still open: gh pr close ${pr%% *}"
  fi
  if ((rc)); then
    echo "conflict dropping $l's merged commits from ${lpath[$child]}: resolve, git -C ${lpath[$child]} rebase --continue, then wts sync" >&2
    exit 1
  fi
  status
}

sync() {
  local main=0 force=0 a i b p lp top old new
  for a in "$@"; do
    case "$a" in
    --main) main=1 ;;
    --force) force=1 ;;
    *) die "unknown flag $a" ;;
    esac
  done
  load
  ((${#order[@]})) || die "$name is not a stack"
  for b in "${order[@]}"; do
    ! in_rebase "${lpath[$b]}" || die "$(lname "$b") is mid-rebase: resolve, git -C ${lpath[$b]} rebase --continue, then wts sync"
  done

  # Newer pushes (the PR author restacked, or you pushed from elsewhere): a
  # layer whose local-only commits were all on origin before is an older copy,
  # so it moves to origin. reset --keep carries uncommitted changes along and
  # refuses if they'd clash.
  fetch_origin || die "git fetch origin failed"
  for b in "${order[@]}"; do
    git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null || continue
    if [ "$(git rev-parse "$b")" = "$(git rev-parse "origin/$b")" ] || [ -n "$(unseen "$b")" ]; then continue; fi
    git -C "${lpath[$b]}" reset -q --keep "origin/$b" ||
      die "$(lname "$b"): its uncommitted changes clash with the newer origin/$b; commit or stash them, then wts sync"
    echo "$(lname "$b"): picked up origin/$b"
  done

  if ((main)); then
    # Moving the bottom moves every layer above it.
    ((force)) || for b in "${order[@]}"; do guard "$b" "sync --main"; done
    b=${order[0]}
    git -C "${lpath[$b]}" rebase -q --autostash "origin/$trunk" ||
      die "conflict moving $(lname "$b") onto $trunk: resolve in ${lpath[$b]}, git -C ${lpath[$b]} rebase --continue, then wts sync"
  fi
  for ((i = 1; i < ${#order[@]}; i++)); do
    b=${order[$i]} p=${order[$i - 1]} lp=${lpath[${order[$i]}]}
    git merge-base --is-ancestor "$p" "$b" && continue
    ((force)) || guard "$b" sync
    # --fork-point reads the parent's reflog, so only this layer's own commits
    # move: whatever the parent dropped or rewrote stays dropped.
    git -C "$lp" rebase -q --autostash --fork-point "$p" ||
      die "conflict restacking $(lname "$b") onto $(lname "$p"): resolve in $lp, git -C $lp rebase --continue, then wts sync"
  done

  top=${order[-1]}
  git branch -q --set-upstream-to="$top" "$root_b"
  if in_rebase "$root"; then
    echo "root is mid-rebase; left alone" >&2
  elif git diff --quiet "$top" "$root_b"; then
    # Same tree: swap history only. update-ref touches neither the index nor
    # the files the user is editing, and refuses if root moved meanwhile.
    old=$(git rev-parse "$root_b") new=$(git rev-parse "$top")
    [ "$old" = "$new" ] || git update-ref -m "wts sync: root = $top" "refs/heads/$root_b" "$new" "$old" ||
      echo "root moved during sync; run wts sync again" >&2
  elif ! git merge-base --is-ancestor "$top" "$root_b"; then
    # Replay root's own commits (if any) onto the new top. Never leave the
    # user's worktree mid-rebase: on conflict, put it back exactly as it was.
    git -C "$root" rebase -q --autostash --fork-point "$top" || {
      git -C "$root" rebase --abort
      echo "root: its own commits don't replay onto $(lname "$top"); left untouched — move what's missing into layers, then wts sync" >&2
    }
  fi
  status
}

pull() {
  local a pr="" nm="" rows n h bs f t i me top rb rp rs ps setup l b cur="" here here_b="" kids=() stack=() stale=() names=()
  local -A head=() num=() base=() who=() fork=() title=() used=()
  while (($#)); do
    case "$1" in
    --root)
      nm=${2:-}
      [ -n "$nm" ] || die "--root needs a name"
      shift 2
      ;;
    --root=*) nm=${1#--root=} && shift ;;
    -*) die "unknown flag $1" ;;
    *)
      if [ -z "$pr" ] && ((${#names[@]} == 0)) && [[ "${1#\#}" =~ ^[0-9]+$ ]]; then pr=${1#\#}; else names+=("$1"); fi
      shift
      ;;
    esac
  done
  repo
  # A plain wt worktree we're standing in (not a stack root or layer) becomes
  # the root, unless --root asks for a new one; its branch picks the default PR.
  here=$(git rev-parse --show-toplevel)
  if [[ "$here" == "$wd"/* && "${here#"$wd"/}" != */* && ! -d "$wd/.stacks/${here#"$wd"/}" ]]; then
    cur=${here#"$wd"/}
    here_b=$(git branch --show-current)
  fi

  rows=$(cd "$main_root" && gh pr list --state open --limit 200 \
    --json number,headRefName,baseRefName,author,isCrossRepository,title \
    --jq '.[] | [.number, .headRefName, .baseRefName, .author.login, .isCrossRepository, .title] | @tsv') ||
    die "gh pr list failed"
  while IFS=$'\t' read -r n h bs a f t; do
    [ -n "$n" ] || continue
    head[$n]=$h num[$h]=$n base[$h]=$bs who[$h]=$a fork[$h]=$f title[$h]=$t
  done <<<"$rows"
  if [ -z "$pr" ]; then
    [ -n "$here_b" ] && [ -n "${num[$here_b]+x}" ] ||
      die "this worktree's branch has no open PR (merged, or never opened): wts pull <pr#>"
    pr=${num[$here_b]}
  fi
  [[ "$pr" =~ ^[0-9]+$ ]] || die "usage: wts pull [pr#] [--root <name>] [<layer name>...]"
  [ -n "${head[$pr]+x}" ] || die "#$pr is not an open PR in this repo"

  # Down to the PR based on trunk, then up through whatever sits on top.
  h=${head[$pr]} stack=("$h")
  while [ -n "${num[${base[$h]}]+x}" ]; do
    h=${base[$h]}
    ((${#stack[@]} < 50)) || die "PR bases form a loop around $h"
    stack=("$h" "${stack[@]}")
  done
  [ "${base[$h]}" = "$trunk" ] ||
    die "the bottom PR #${num[$h]} is based on ${base[$h]}, not $trunk; if that is this stack's trunk: git config wts.trunk ${base[$h]}"
  h=${head[$pr]}
  while :; do
    kids=()
    for b in "${!base[@]}"; do [ "${base[$b]}" != "$h" ] || kids+=("#${num[$b]}"); done
    ((${#kids[@]})) || break
    ((${#kids[@]} == 1)) || die "several PRs sit on #${num[$h]} (${kids[*]}): wts pull the one that should be the top"
    h=${head[${kids[0]#\#}]}
    ((${#stack[@]} < 50)) || die "PR bases form a loop around $h"
    stack+=("$h")
  done

  [ -z "$nm" ] || cur=""
  if [ -n "$cur" ]; then
    if [ -z "$here_b" ] && [ -n "$(git rev-list -1 HEAD --not --branches --remotes)" ]; then
      die "this worktree's detached HEAD has commits no branch holds: git branch <name> first, so nothing is lost when it becomes the stack root"
    fi
    nm=$cur
  else
    : "${nm:=pr$pr}"
    valid_name "$nm" || die "stack names are short: lowercase letters, digits and '-', at most 16 chars (got '$nm')"
  fi
  rp="$wd/$nm" rb="$(git config --default "" wt.prefix)$nm"
  [ -n "$cur" ] || [ ! -e "$rp" ] || die "$rp already exists: pick another name (wts pull $pr --root <name> ...)"
  ! git show-ref -q --verify "refs/heads/$rb" || die "branch $rb already exists: delete it, or pick another name"
  for b in "${stack[@]}"; do
    [ "${fork[$b]}" = false ] || die "#${num[$b]} comes from a fork; wts only pulls branches that live on origin"
    f=$(git for-each-ref --format='%(worktreepath)' "refs/heads/$b")
    if [ -n "$f" ] && ! { [ -n "$cur" ] && [ "$f" = "$here" ]; }; then
      die "$b is checked out at $f: remove that worktree first, or run wts pull there"
    fi
  done

  # Naming is the caller's: list the PRs, so each layer gets a name that means
  # something, then take one name per PR on the next call.
  if ((${#names[@]} == 0)); then
    echo "#$pr is part of a stack of $(plural ${#stack[@]} PR) on $trunk, bottom → top:"
    for i in "${!stack[@]}"; do
      b=${stack[$i]}
      printf '%3d #%s @%s  %s\n      %s\n' $((i + 1)) "${num[$b]}" "${who[$b]}" "$b" "${title[$b]}"
    done
    if [ -n "$cur" ]; then
      echo "root: this worktree ($cur), switched to a new branch $rb at the top PR${here_b:+ ($here_b stays as a branch)}"
      echo "      (--root <name> makes a new worktree instead)"
      f=""
    else
      echo "root: a new worktree $rp (--root <name> to name it)"
      f=" [--root <name>]"
    fi
    echo "name each PR's layer from its title: lowercase letters, digits and '-', at most 16 chars, then:"
    echo "  wts pull $pr$f <${#stack[@]} layer names, bottom → top>"
    return 0
  fi
  ((${#names[@]} == ${#stack[@]})) ||
    die "#$pr's stack has $(plural ${#stack[@]} PR) but got $(plural ${#names[@]} name): one per PR, bottom → top (wts pull $pr lists them)"
  for l in "${names[@]}"; do
    valid_name "$l" || die "layer names are short: lowercase letters, digits and '-', at most 16 chars, not 'trunk' (got '$l')"
    [ -z "${used[$l]+x}" ] || die "layer name '$l' is used twice"
    used[$l]=1
  done

  # Fresh remote state. A local copy that is only an older origin (say, from
  # before a force-push) is moved to origin; one with real unpushed work is kept.
  fetch_origin || die "git fetch origin failed"
  for b in "${stack[@]}"; do
    git show-ref -q --verify "refs/heads/$b" || continue
    n=$(unpushed "$b" | wc -l | tr -d ' ')
    if ((n)); then
      echo "note: local $b has $n commit(s) origin/$b lacks; kept the local branch"
    else
      stale+=("$b")
    fi
  done
  me=$(cd "$main_root" && gh api user --jq .login 2>/dev/null || true)

  # Root starts at the top PR, so it reads "= top" from the start.
  top=${stack[-1]} rs=$top
  if ! git show-ref -q --verify "refs/heads/$top" || [[ " ${stale[*]} " == *" $top "* ]]; then
    rs=$(git rev-parse "origin/$top")
  fi
  if [ -n "$cur" ]; then
    # git refuses (changing nothing) if uncommitted changes would be overwritten.
    git -C "$rp" switch -q -c "$rb" "$rs" ||
      die "could not move this worktree to the top PR; commit or stash first"
  fi
  for b in ${stale[@]+"${stale[@]}"}; do
    git update-ref -m "wts pull: match origin" "refs/heads/$b" "refs/remotes/origin/$b"
  done
  if [ -z "$cur" ]; then
    mkdir -p "$wd"
    wt-claim "$main_root" "$rp" "$rb" "$rs" ||
      wt-create "$main_root" "$rp" "$rb" "$rs" ||
      die "could not create $rp (log: $wd/.$nm.log)"
    ps=$(parent_session)
    if [ -n "$ps" ]; then
      setup="$wd/.setup"
      [ -f "$setup" ] || setup=""
      tmux has-session -t "=$ps/$nm" 2>/dev/null ||
        tmux new-session -d -s "$ps/$nm" -c "$rp" \
          "'$(command -v wt-enter)' '$main_root' '$rp' '$rb' '$rs' '$ps/$nm' '$setup'"
    fi
  fi

  cd "$rp" || die "cannot enter $rp"
  ctx
  for i in "${!stack[@]}"; do
    b=${stack[$i]}
    add_layer "${names[$i]}" "$b" >/dev/null
    if [ -n "$me" ] && [ "${who[$b]}" = "$me" ]; then
      git config --unset "branch.$b.wtsAuthor" || true
    else
      git config "branch.$b.wtsAuthor" "${who[$b]}"
      # No such remote: a bare `git push` here fails; `git push origin <b>` works.
      git config "branch.$b.pushRemote" ask-the-user
    fi
  done
  pool_fill
  echo "pulled the stack of #$pr (${#stack[@]} PRs) into $rp"
  status
}

# For the tmux picker: "<stack>\t<position, 0 = root>\t<root commits not in
# top>\t<1 if behind its parent>". Prints nothing outside a stack.
key() {
  local i b top pend=0 behind=0
  load
  ((${#order[@]})) || return 0
  top=${order[-1]}
  if [ "$here" = "$root" ]; then
    if ! git diff --quiet "$top" "$root_b"; then
      pend=$(git rev-list --count "$top..$root_b")
      git merge-base --is-ancestor "$top" "$root_b" || behind=1
    fi
    printf '%s\t0\t%s\t%s\n' "$name" "$pend" "$behind"
    return 0
  fi
  for i in "${!order[@]}"; do
    b=${order[$i]}
    [ "${lpath[$b]}" = "$here" ] || continue
    ((i == 0)) || git merge-base --is-ancestor "${order[$i - 1]}" "$b" || behind=1
    printf '%s\t%s\t0\t%s\n' "$name" $((i + 1)) "$behind"
  done
}

cmd=${1:-}
[ $# -eq 0 ] || shift
case "$cmd" in
help | -h | --help) usage && exit 0 ;;
pull)
  pull "$@"
  exit
  ;;
esac
ctx
case "$cmd" in
"" | status) status ;;
add) add "$@" ;;
rm) rm_layer "$@" ;;
sync) sync "$@" ;;
_key) key ;;
*) usage >&2 && exit 2 ;;
esac
