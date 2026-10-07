// Git and pull request state for the sidebar's Git section. Display only:
// none of it reaches the model's context.
//
// Local state (branch, distance from the default branch, uncommitted files)
// is re-read on session start, after each turn and after tool calls that can
// touch the tree. A background fetch of the default branch every FETCH_MS
// keeps "behind" honest. The fetch goes over HTTPS with gh's token rather
// than the SSH remote, so it can never raise an SSH agent prompt.
//
// The PR comes from gh and is shared between every open omo through a cache
// file per repo and branch in TMPDIR, as core/limits.ts shares usage: each omo
// re-reads it every READ_MS, and whichever finds it older than PR_TTL_MS and
// wins the lock fetches while the rest just read. A failed fetch keeps the
// last known PR and waits out the TTL like a successful one.
//
// The gh call mirrors pr_row in modules/cli/tmux/session-picker.nix: one
// `gh pr list --head` per branch, never --author @me (search index, answers
// an empty success while it lags) or repo-wide --state listings with the
// rollup (they fail on a busy monorepo). Its comments have the details.
import { execFile } from "node:child_process"
import { createHash } from "node:crypto"
import { readFileSync, renameSync, statSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { requestRender } from "./host.ts"
import { lock, unlock } from "./lock.ts"
import type { Ctx } from "./types.ts"

export type GitState = {
  cwd: string
  // The common git dir: one per repo, shared by its worktrees.
  repo: string
  // Empty when HEAD is detached; `head` is the short commit then.
  branch: string
  head: string
  // The remote's default branch (origin/HEAD); empty without an origin.
  base: string
  behind: number
  ahead: number
  uncommitted: number
  untracked: number
  conflicted: number
}

export type Pr = {
  number: number
  url: string
  state: "OPEN" | "MERGED"
  draft: boolean
  base: string
  checks: "none" | "pass" | "pending" | "fail"
  failing: string[]
  running: number
  // gh's reviewDecision: APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED or "".
  review: string
  conflict: boolean
  unresolved: number
}

type Check = { name?: string; context?: string; conclusion?: string; status?: string; state?: string }
type GhPr = {
  number: number
  url: string
  state: string
  isDraft: boolean
  baseRefName: string
  statusCheckRollup?: Check[]
  reviewDecision?: string
  mergeable?: string
}
type Cache = { at: number; pr: Pr | null }
type Pi = { on(event: string, handler: (event: { toolName?: string }, ctx: Ctx) => void): void }

const READ_MS = 15_000
const PR_TTL_MS = 60_000
const FETCH_MS = 5 * 60_000
// Both gh calls of one PR fetch, and the git fetch, finish well inside
// core/lock.ts's stale threshold.
const GH_TIMEOUT_MS = 10_000
const FETCH_TIMEOUT_MS = 20_000
const GIT_TIMEOUT_MS = 10_000
// Tools that can change the working tree or move HEAD. eval runs shell
// commands through its tool.bash.
const TREE_TOOLS = new Set(["edit", "write", "bash", "eval"])
// The CI classification of pr_row: a failure wins, then anything running.
const FAILED = new Set(["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "FAILED", "STARTUP_FAILURE"])
const RUNNING = new Set(["IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "REQUESTED"])
const WAITING = new Set(["PENDING", "EXPECTED"])
const PR_FIELDS = "number,url,state,isDraft,baseRefName,statusCheckRollup,reviewDecision,mergeable"
// 100 threads is GraphQL's page limit; a PR with more undercounts.
const THREADS_QUERY = `query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { reviewThreads(first: 100) { nodes { isResolved } } }
  }
}`
// /reload imports a fresh copy of this module; the timer lives on globalThis
// so the new copy replaces the old poller instead of running beside it.
const TIMER = Symbol.for("omo-ui.git.timer")

export const git = { state: undefined as GitState | undefined, pr: undefined as Pr | undefined }

let cwd: string | undefined
let started = false
let reading = false
let again = false

// Never a prompt: no terminal for credentials, and no optional index lock
// that could collide with the agent's own git commands.
function run(cmd: string, args: string[], dir: string, timeout: number): Promise<string> {
  const env = { ...process.env, GIT_OPTIONAL_LOCKS: "0", GIT_TERMINAL_PROMPT: "0" }
  return new Promise((done, fail) =>
    execFile(cmd, args, { cwd: dir, env, timeout, maxBuffer: 16 << 20 }, (error: Error | null, stdout: string) =>
      error ? fail(error) : done(stdout),
    ),
  )
}

const gitOut = (dir: string, ...args: string[]) =>
  run("git", args, dir, GIT_TIMEOUT_MS).then(
    (out) => out.trim(),
    () => "",
  )

async function defaultBranch(dir: string): Promise<string> {
  const head = await gitOut(dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
  if (head) return head.replace(/^origin\//, "")
  for (const name of ["main", "master"]) {
    if (await gitOut(dir, "rev-parse", "--verify", "--quiet", `refs/remotes/origin/${name}`)) return name
  }
  return ""
}

async function read(dir: string): Promise<GitState | undefined> {
  const repo = await gitOut(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
  if (!repo) return undefined
  const [branch, head, base, status] = await Promise.all([
    gitOut(dir, "branch", "--show-current"),
    gitOut(dir, "rev-parse", "--short", "HEAD"),
    defaultBranch(dir),
    run("git", ["status", "--porcelain"], dir, GIT_TIMEOUT_MS).catch(() => ""),
  ])
  const counts = base ? await gitOut(dir, "rev-list", "--left-right", "--count", `refs/remotes/origin/${base}...HEAD`) : ""
  const [behind = 0, ahead = 0] = counts.split(/\s+/).map(Number)
  const state: GitState = { cwd: dir, repo, branch, head, base, behind, ahead, uncommitted: 0, untracked: 0, conflicted: 0 }
  for (const line of status.split("\n")) {
    const xy = line.slice(0, 2)
    if (xy.length < 2) continue
    if (xy === "??") state.untracked++
    else if (xy.includes("U") || xy === "AA" || xy === "DD") state.conflicted++
    else state.uncommitted++
  }
  return state
}

// Calls landing while a read runs fold into one more read after it.
export function refreshGit(next?: string): void {
  if (next) cwd = next
  if (!started || !cwd || reading) {
    if (reading) again = true
    return
  }
  reading = true
  void read(cwd)
    .then((state) => {
      const moved = state?.repo !== git.state?.repo || state?.branch !== git.state?.branch
      git.state = state
      if (moved) {
        git.pr = undefined
        void pollPr()
      }
      requestRender()
    })
    .finally(() => {
      reading = false
      if (again) {
        again = false
        refreshGit()
      }
    })
}

const hash = (text: string) => createHash("sha1").update(text).digest("hex").slice(0, 16)

function readCache(file: string): Cache | undefined {
  try {
    return JSON.parse(readFileSync(file, "utf8"))
  } catch {
    return undefined
  }
}

function writeCache(file: string, cache: Cache): void {
  const tmp = `${file}.${process.pid}`
  writeFileSync(tmp, JSON.stringify(cache))
  renameSync(tmp, file)
}

async function unresolvedThreads(dir: string, url: string): Promise<number> {
  const [, owner, name, number] = url.match(/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/) ?? []
  if (!number) return 0
  const out = await run(
    "gh",
    [
      "api",
      "graphql",
      "-f",
      `query=${THREADS_QUERY}`,
      "-f",
      `owner=${owner}`,
      "-f",
      `name=${name}`,
      "-F",
      `number=${number}`,
      "--jq",
      "[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length",
    ],
    dir,
    GH_TIMEOUT_MS,
  )
  return Number(out.trim()) || 0
}

// Newest open PR wins, else newest merged; a closed-unmerged one is no PR.
async function fetchPr(dir: string, branch: string): Promise<Pr | null> {
  const args = ["pr", "list", "--head", branch, "--state", "all", "--limit", "10", "--json", PR_FIELDS]
  const list: GhPr[] = JSON.parse(await run("gh", args, dir, GH_TIMEOUT_MS))
  const newest = (state: string) => list.filter((p) => p.state === state).sort((a, b) => b.number - a.number)[0]
  const p = newest("OPEN") ?? newest("MERGED")
  if (!p) return null
  const pr: Pr = {
    number: p.number,
    url: p.url,
    state: p.state === "MERGED" ? "MERGED" : "OPEN",
    draft: p.isDraft,
    base: p.baseRefName,
    checks: "none",
    failing: [],
    running: 0,
    review: p.reviewDecision ?? "",
    conflict: false,
    unresolved: 0,
  }
  // Merged collapses to just that in the sidebar; nothing else is fetched.
  if (pr.state === "MERGED") return pr
  const rollup = p.statusCheckRollup ?? []
  pr.failing = [...new Set(rollup.filter((c) => FAILED.has(c.conclusion || c.state || "")).map((c) => c.name || c.context || "check"))]
  pr.running = rollup.filter((c) => RUNNING.has(c.status ?? "") || WAITING.has(c.state ?? "")).length
  pr.checks = rollup.length === 0 ? "none" : pr.failing.length > 0 ? "fail" : pr.running > 0 ? "pending" : "pass"
  pr.conflict = p.mergeable === "CONFLICTING"
  pr.unresolved = await unresolvedThreads(dir, p.url)
  return pr
}

async function pollPr(): Promise<void> {
  const s = git.state
  // The default branch is never a PR head; detached HEAD has no branch.
  if (!s?.branch || s.branch === s.base) return
  const show = (pr: Pr | null | undefined) => {
    if (git.state?.repo !== s.repo || git.state.branch !== s.branch) return
    git.pr = pr ?? undefined
    requestRender()
  }
  const file = join(tmpdir(), `omo-pr-${hash(`${s.repo}\0${s.branch}`)}.json`)
  const cached = readCache(file)
  if (cached) show(cached.pr)
  if (cached && Date.now() - cached.at < PR_TTL_MS) return
  if (!lock(`${file}.lock`)) return
  try {
    // Another omo may have finished a fetch between the read above and
    // taking the lock.
    const latest = readCache(file)
    if (latest && Date.now() - latest.at < PR_TTL_MS) return show(latest.pr)
    const pr = await fetchPr(s.cwd, s.branch).catch(() => cached?.pr ?? null)
    writeCache(file, { at: Date.now(), pr })
    show(pr)
  } finally {
    unlock(`${file}.lock`)
  }
}

const age = (file: string) => {
  try {
    return Date.now() - statSync(file).mtimeMs
  } catch {
    return Number.POSITIVE_INFINITY
  }
}

// One fetch per repo every FETCH_MS across all omos: the stamp file's mtime
// is the last attempt, and a failure waits it out too, silently.
async function fetchBase(): Promise<void> {
  const s = git.state
  if (!s?.base) return
  const stamp = join(tmpdir(), `omo-git-fetch-${hash(s.repo)}`)
  if (age(stamp) < FETCH_MS || !lock(`${stamp}.lock`)) return
  try {
    if (age(stamp) < FETCH_MS) return
    const remote = await gitOut(s.cwd, "remote", "get-url", "origin")
    const slug = remote.match(/github\.com[:/]([^/]+\/[^/]+?)(?:\.git)?\/?$/)?.[1]
    if (!slug) return
    const helper = ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"]
    const refspec = `+refs/heads/${s.base}:refs/remotes/origin/${s.base}`
    const args = [...helper, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", `https://github.com/${slug}.git`, refspec]
    await run("git", args, s.cwd, FETCH_TIMEOUT_MS).catch(() => undefined)
    writeFileSync(stamp, "")
  } finally {
    unlock(`${stamp}.lock`)
  }
  refreshGit()
}

export function initGit(pi: Pi): void {
  pi.on("session_start", (_e, ctx) => refreshGit(ctx.cwd))
  pi.on("turn_end", (_e, ctx) => refreshGit(ctx.cwd))
  pi.on("tool_result", (e, ctx) => {
    if (TREE_TOOLS.has(e.toolName ?? "")) refreshGit(ctx.cwd)
  })
}

// Polls only where there is a screen to show it: headless workers never
// mount a tui, so they never run git or gh here.
export function startGit(): void {
  started = true
  const slots = globalThis as Record<symbol, ReturnType<typeof setInterval> | undefined>
  clearInterval(slots[TIMER])
  const timer = setInterval(() => {
    void pollPr()
    void fetchBase()
  }, READ_MS)
  // Never the reason omo's process stays alive on exit.
  ;(timer as { unref?(): void }).unref?.()
  slots[TIMER] = timer
  refreshGit()
  void fetchBase()
}
