// agent — drive omo sessions from outside, over omo's shared RPC host
// (experimental.sharedHost): every interactive omo joins one host at
// ~/.omo/agent/rpc/rpc.sock, and this attaches to a session there by its file
// path without taking it over. Talk, status and question answers are protocol
// calls, not keystrokes; tmux is only used to create sessions (spawn), switch
// the client to one (open) and read a screen that isn't on the host (peek).
import { spawnSync } from "node:child_process"
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs"
import { createConnection, type Socket } from "node:net"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"

type Msg = Record<string, any>
type Row = { sessionId: string; durableSessionId: string; sessionPath: string; cwd: string; status: string; name: string }
type Question = { id: string; header?: string; question: string; multiSelect?: boolean; options?: { label: string; description?: string }[] }
type Pending = { id: string; requestId?: string; questions: Question[] }

const AGENT_DIR = process.env.OMO_CODING_AGENT_DIR ?? join(homedir(), ".omo/agent")
const SOCKET = join(AGENT_DIR, "rpc/rpc.sock")

const USAGE = `agent — talk to omo sessions over omo's shared RPC host

  agent ls [--all]                 this project's sessions: name, state, context, PR, task
  agent status <name>              state, branch, PR, open questions and the last reply
  agent talk <name> [--after] <message|->
                                   steer a busy agent (after its current tool batch),
                                   or start its next turn; --after queues for when it stops
  agent questions <name>           open questions with numbered options
  agent answer <name> <q>=<choice>[,<choice>]... [--text <q>=<text>] [--comment <text>]
                                   answer every open question in one call; a choice is an
                                   option number or label; with one question the "q1=" can go
  agent wait <name> [--timeout <s>]
                                   block until the agent is idle or asks something (default 1800s)
  agent log <name> [n]             its last n replies (default 1)
  agent spawn <name> <prompt|->    new wt worktree + tmux session running omo with prompt
  agent spawn --stack <root> [--after <layer>] <layer> <prompt|->
                                   the same as a layer of the wts stack <root> (made if new)
  agent spawn ... --needs <name>[,<name>] <name> <prompt|->
                                   create it now, start omo once those agents are done
                                   (idle, clean worktree, own commits); ls shows it waiting
  agent await <name>[,<name>]      block until those agents are done (what --needs runs)
  agent open <name>                switch your tmux client to its session
  agent peek <name> [lines]        its tmux screen (fallback for sessions not on the host)

<name> is the worktree name ("main" for the main checkout, <root>/<layer> for a
stack layer) or a session id prefix.

Pass any message longer than a few plain words on stdin with a quoted heredoc,
so backticks and $(...) stay literal:
  agent talk core - <<'EOF'
  Rename \`foo\` to \`bar\`.
  EOF`

// Starts every message this CLI relays; the agents extension tells sessions
// it means "from the user's orchestrator, on the user's behalf".
const MARK = "[orchestrator] "

function die(message: string): never {
  process.stderr.write(`agent: ${message}\n`)
  process.exit(1)
}

class Rpc {
  private buf = ""
  private seq = 0
  private waiting = new Map<string, (m: Msg) => void>()
  private listeners = new Set<(m: Msg) => void>()
  private constructor(private sock: Socket) {
    sock.on("data", (d) => {
      this.buf += d
      let k: number
      while ((k = this.buf.indexOf("\n")) >= 0) {
        const line = this.buf.slice(0, k)
        this.buf = this.buf.slice(k + 1)
        let m: Msg
        try {
          m = JSON.parse(line)
        } catch {
          continue
        }
        if (m.type === "response" && this.waiting.has(m.id)) {
          this.waiting.get(m.id)?.(m)
          this.waiting.delete(m.id)
        }
        for (const l of this.listeners) l(m)
      }
    })
  }

  static connect(): Promise<Rpc> {
    if (!existsSync(SOCKET)) die(`no shared omo host at ${SOCKET} (is experimental.sharedHost on, and an omo running?)`)
    return new Promise((resolve, reject) => {
      const sock = createConnection(SOCKET)
      sock.once("connect", () => resolve(new Rpc(sock)))
      sock.once("error", (e) => reject(new Error(`cannot reach ${SOCKET}: ${e.message}`)))
    })
  }

  async request(type: string, fields: Msg = {}): Promise<Msg> {
    const id = `agent-${++this.seq}`
    const reply = new Promise<Msg>((resolve) => this.waiting.set(id, resolve))
    this.sock.write(`${JSON.stringify({ id, type, ...fields })}\n`)
    const m = await reply
    if (!m.success) throw new Error(`${type}: ${typeof m.error === "string" ? m.error : JSON.stringify(m.error)}`)
    return m.data ?? {}
  }

  send(m: Msg) {
    this.sock.write(`${JSON.stringify(m)}\n`)
  }

  until<T>(pick: (m: Msg) => T | undefined, ms: number): Promise<T | undefined> {
    return new Promise((resolve) => {
      const done = (v: T | undefined) => {
        clearTimeout(timer)
        this.listeners.delete(listener)
        resolve(v)
      }
      const listener = (m: Msg) => {
        const v = pick(m)
        if (v !== undefined) done(v)
      }
      const timer = setTimeout(() => done(undefined), ms)
      this.listeners.add(listener)
    })
  }

  // Disconnecting releases only this client's attachment; close_session would
  // abort the agent's work.
  close() {
    this.sock.destroy()
  }
}

// Sessions are named after where they run: "main" for the main checkout, the
// path under <repo>.worktrees/ for a wt worktree.
function project(): { main: string; worktrees: string } | undefined {
  const r = spawnSync("git", ["worktree", "list", "--porcelain"], { encoding: "utf8" })
  if (r.status !== 0) return undefined
  const main = realpathSync(r.stdout.split("\n")[0].replace(/^worktree /, ""))
  return { main, worktrees: `${main}.worktrees` }
}

function nameOf(cwd: string, p: ReturnType<typeof project>): string | undefined {
  if (!p) return undefined
  if (cwd === p.main) return "main"
  // wts layers live in .stacks/<root>/<layer>; named like their tmux session.
  if (cwd.startsWith(`${p.worktrees}/`)) return cwd.slice(p.worktrees.length + 1).replace(/^\.stacks\//, "")
}

function git(cwd: string, args: string[]): string | undefined {
  const r = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8" })
  return r.status === 0 ? r.stdout.trim() : undefined
}

type Pr = { number: number; state: string; headRefName: string }

// One gh call per listing; no gh, no auth or no remote just means no PR column.
function prsByBranch(p: ReturnType<typeof project>): Map<string, Pr> {
  const map = new Map<string, Pr>()
  if (!p) return map
  const r = spawnSync("gh", ["pr", "list", "--state", "all", "--limit", "200", "--json", "number,state,headRefName"], { cwd: p.main, encoding: "utf8" })
  if (r.status !== 0) return map
  for (const pr of JSON.parse(r.stdout) as Pr[]) if (!map.has(pr.headRefName)) map.set(pr.headRefName, pr)
  return map
}

function prOf(prs: Map<string, Pr>, cwd: string): string {
  const pr = prs.get(git(cwd, ["branch", "--show-current"]) ?? "")
  return pr ? `#${pr.number} ${pr.state.toLowerCase()}` : "-"
}

async function rows(rpc: Rpc, all: boolean): Promise<Row[]> {
  const p = project()
  const { sessions } = await rpc.request("list_sessions")
  return (sessions as Omit<Row, "name">[])
    .filter((s) => s.status === "open")
    .map((s) => ({ ...s, name: nameOf(s.cwd, p) ?? "" }))
    .filter((s) => all || !p || s.name)
    .map((s) => ({ ...s, name: s.name || s.cwd.replace(homedir(), "~") }))
    .sort((a, b) => b.sessionPath.localeCompare(a.sessionPath))
}

// Newest session wins when several run in one worktree.
async function resolve(rpc: Rpc, target: string | undefined): Promise<Row> {
  if (!target) die("missing <name>")
  const all = await rows(rpc, true)
  const row = all.find((r) => r.name === target) ?? all.find((r) => r.durableSessionId.startsWith(target))
  if (!row) die(`no session "${target}" on the host; running: ${all.map((r) => r.name).join(", ") || "none"}`)
  return row
}

async function attach(rpc: Rpc, row: Row): Promise<{ sid: string; state: Msg }> {
  const { sessionId } = await rpc.request("open_session", { sessionPath: row.sessionPath })
  return { sid: sessionId, state: await rpc.request("get_state", { sessionId }) }
}

function stateOf(state: Msg): "question" | "busy" | "idle" {
  if (state.pendingQuestions?.length) return "question"
  return state.isStreaming || state.isCompacting ? "busy" : "idle"
}

function contextOf(state: Msg): string {
  const u = state.contextUsage ?? {}
  const pct = u.percent ?? u.percentage
  return typeof pct === "number" ? `${Math.round(pct)}%` : "-"
}

function entries(path: string): Msg[] {
  if (!existsSync(path)) return []
  return readFileSync(path, "utf8")
    .split("\n")
    .flatMap((l) => {
      try {
        return [JSON.parse(l)]
      } catch {
        return []
      }
    })
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content
  return Array.isArray(content) ? content.filter((c) => c?.type === "text").map((c) => c.text).join("") : ""
}

function messages(path: string, role: string): string[] {
  return entries(path)
    .filter((e) => e.type === "message" && e.message?.role === role)
    .map((e) => textOf(e.message.content).trim())
    .filter(Boolean)
}

function taskOf(path: string): string {
  const first = messages(path, "user")[0] ?? ""
  const line = (first.startsWith(MARK) ? first.slice(MARK.length) : first).split("\n")[0]
  return line.length > 80 ? `${line.slice(0, 79)}…` : line
}

function formatQuestions(pending: Pending[]): string {
  return pending
    .flatMap((p) =>
      p.questions.map((q) =>
        [
          `${q.id}${q.header ? ` [${q.header}]` : ""} ${q.question}${q.multiSelect ? " (several allowed)" : ""}`,
          ...(q.options ?? []).map((o, i) => `  ${i + 1}. ${o.label}${o.description ? ` — ${o.description}` : ""}`),
        ].join("\n"),
      ),
    )
    .join("\n")
}

async function printStatus(rpc: Rpc, row: Row) {
  const { state } = await attach(rpc, row)
  const queued = (state.steering?.length ?? 0) + (state.followUp?.length ?? 0)
  const lines = [
    `${row.name}: ${stateOf(state)} · ${state.model?.name ?? state.model?.id ?? "no model"} · context ${contextOf(state)}${queued ? ` · ${queued} queued` : ""}`,
    `cwd: ${row.cwd}`,
    `task: ${taskOf(row.sessionPath)}`,
  ]
  const branch = git(row.cwd, ["branch", "--show-current"])
  if (branch) {
    const counts = git(row.cwd, ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])?.split(/\s+/)
    const upstream = git(row.cwd, ["rev-parse", "--abbrev-ref", "@{upstream}"])
    const drift = counts && upstream ? ` · ${counts[0]} ahead, ${counts[1]} behind ${upstream}` : ""
    lines.push(`branch: ${branch}${drift} · PR ${prOf(prsByBranch(project()), row.cwd)}`)
  }
  if (state.pendingQuestions?.length) lines.push("", formatQuestions(state.pendingQuestions), "", `answer: agent answer ${row.name} <q>=<choice>`)
  const last = messages(row.sessionPath, "assistant").pop()
  if (last && !state.pendingQuestions?.length) lines.push("", "last reply:", last)
  console.log(lines.join("\n"))
}

async function readArg(rest: string[]): Promise<string> {
  const text = rest.length === 1 && rest[0] === "-" ? await Bun.stdin.text() : rest.join(" ")
  if (!text.trim()) die("empty message")
  return text
}

function tmux(args: string[], what: string): string {
  const r = spawnSync("tmux", args, { encoding: "utf8" })
  if (r.status !== 0) die(`${what}: ${(r.stderr || r.stdout).trim() || `exit ${r.status}`}`)
  return r.stdout.trim()
}

// wt names sessions "<root tmux session>/<name>".
function tmuxSession(name: string): string {
  if (!process.env.TMUX) die("needs to run inside tmux")
  return `${tmux(["display-message", "-p", "#{session_name}"], "tmux").split("/")[0]}/${name}`
}

// The tmux session started in a worktree (wt and wts both pass -c <path>).
function sessionAt(path: string): string | undefined {
  const want = realpathSync(path)
  return tmux(["list-sessions", "-F", "#{session_path}\t#{session_name}"], "tmux")
    .split("\n")
    .map((l) => l.split("\t"))
    .find(([sp]) => existsSync(sp) && realpathSync(sp) === want)?.[1]
}

// The pane omo announced itself in (tmux-notifier sets @oc-sid), else the first.
function paneOf(session: string): string {
  const panes = tmux(["list-panes", "-s", "-t", `=${session}`, "-F", "#{pane_id}\t#{@oc-sid}"], `no tmux session ${session}`)
    .split("\n")
    .map((l) => l.split("\t"))
  return (panes.find(([, sid]) => sid) ?? panes[0])[0]
}

function option(args: string[], flag: string): string[] {
  const values: string[] = []
  for (let i = args.indexOf(flag); i >= 0; i = args.indexOf(flag)) {
    values.push(args[i + 1] ?? die(`${flag} needs a value`))
    args.splice(i, 2)
  }
  return values
}

function answersFor(pending: Pending, specs: string[], texts: string[]): Record<string, { selected: string[]; text?: string }> {
  const questions = pending.questions
  const byId = (id: string) => questions.find((q) => q.id === id) ?? die(`no question ${id}; open: ${questions.map((q) => q.id).join(", ")}`)
  const split = (spec: string): [Question, string] => {
    const eq = spec.indexOf("=")
    if (eq > 0 && questions.some((q) => q.id === spec.slice(0, eq))) return [byId(spec.slice(0, eq)), spec.slice(eq + 1)]
    if (questions.length === 1) return [questions[0], spec]
    return die(`"${spec}": say which question, e.g. ${questions[0].id}=1`)
  }
  const answers: Record<string, { selected: string[]; text?: string }> = {}
  for (const spec of specs) {
    const [q, value] = split(spec)
    const labels = (q.options ?? []).map((o) => o.label)
    const selected = value.split(",").map((v) => {
      const n = Number(v)
      if (Number.isInteger(n) && n >= 1 && n <= labels.length) return labels[n - 1]
      return labels.find((l) => l.toLowerCase() === v.trim().toLowerCase()) ?? die(`${q.id}: no option "${v}"; options: ${labels.join(", ")}`)
    })
    answers[q.id] = { ...answers[q.id], selected }
  }
  for (const spec of texts) {
    const [q, text] = split(spec)
    answers[q.id] = { selected: answers[q.id]?.selected ?? [], text }
  }
  return answers
}

async function main() {
  const [cmd, ...args] = process.argv.slice(2)
  if (!cmd || cmd === "-h" || cmd === "--help" || cmd === "help") return console.log(USAGE)

  if (cmd === "open" || cmd === "peek") {
    const pane = paneOf(tmuxSession(args[0] ?? die("missing <name>")))
    if (cmd === "open") return void tmux(["switch-client", "-t", pane], "tmux switch-client")
    const n = Math.min(Math.max(1, Number(args[1] ?? 60) || 60), 500)
    return console.log(tmux(["capture-pane", "-p", "-J", "-t", pane, "-S", `-${n}`], "tmux capture-pane"))
  }

  if (cmd === "spawn") {
    const stack = option(args, "--stack")[0]
    const after = option(args, "--after")[0]
    const needs = option(args, "--needs").flatMap((n) => n.split(",")).filter(Boolean)
    if (after && !stack) die("--after needs --stack")
    return spawn(args[0] ?? die("missing <name>"), MARK + (await readArg(args.slice(1))), stack, after, needs)
  }

  if (cmd === "await") return awaitDeps((args[0] ?? die("missing <name>[,<name>]")).split(",").filter(Boolean))

  const rpc = await Rpc.connect()
  try {
    if (cmd === "ls") {
      const list = await rows(rpc, args.includes("--all"))
      const prs = prsByBranch(project())
      const out = [["name", "state", "context", "pr", "task"]]
      for (const row of list) {
        const { state } = await attach(rpc, row)
        out.push([row.name, stateOf(state), contextOf(state), prOf(prs, row.cwd), taskOf(row.sessionPath)])
      }
      for (const [name, needs] of waiting()) if (!list.some((r) => r.name === name)) out.push([name, "waiting", "-", "-", `needs ${needs}`])
      if (out.length === 1) return console.log("no agents")
      const width = out.reduce((w, r) => w.map((x, i) => Math.max(x, r[i].length)), [0, 0, 0, 0])
      return console.log(out.map((r) => r.map((c, i) => (i < 4 ? c.padEnd(width[i]) : c)).join("  ")).join("\n"))
    }

    if (cmd === "status") return await printStatus(rpc, await resolve(rpc, args[0]))

    if (cmd === "log") {
      const row = await resolve(rpc, args[0])
      const n = Math.max(1, Number(args[1] ?? 1) || 1)
      return console.log(messages(row.sessionPath, "assistant").slice(-n).join("\n\n---\n\n") || "(no replies yet)")
    }

    if (cmd === "talk") {
      const after = args.includes("--after")
      const rest = args.filter((a) => a !== "--after")
      const row = await resolve(rpc, rest[0])
      const message = MARK + (await readArg(rest.slice(1)))
      const { sid, state } = await attach(rpc, row)
      const busy = state.isStreaming || state.isCompacting
      const data = await rpc.request("prompt", { sessionId: sid, message, ...(busy ? { streamingBehavior: after ? "followUp" : "steer" } : {}) })
      return console.log(`${row.name}: ${busy ? (after ? "queued for when it stops" : "steering") : "started"}${data.disposition ? ` (${data.disposition})` : ""}`)
    }

    // The question capability makes open questions arrive whole, with ids,
    // instead of omo's one-select-per-question fallback.
    await rpc.request("set_client_info", { capabilities: ["question"], clientInfo: { name: "agent-cli" } })

    if (cmd === "questions") {
      const row = await resolve(rpc, args[0])
      const { state } = await attach(rpc, row)
      const pending: Pending[] = state.pendingQuestions ?? []
      return console.log(pending.length ? `${formatQuestions(pending)}\n\nanswer: agent answer ${row.name} <q>=<choice>` : `${row.name}: no open questions`)
    }

    if (cmd === "answer") {
      const texts = option(args, "--text")
      const comment = option(args, "--comment").join("\n")
      const row = await resolve(rpc, args[0])
      const { sid, state } = await attach(rpc, row)
      const pending: Pending | undefined = state.pendingQuestions?.[0]
      if (!pending) die(`${row.name}: no open questions`)
      const answers = answersFor(pending, args.slice(1), texts)
      const resolved = rpc.until((m) => (m.type === "question_resolved" && m.id === pending.id ? m : undefined), 10_000)
      rpc.send({ type: "extension_ui_response", id: pending.id, sessionId: sid, answers, ...(comment ? { comment } : {}) })
      const r = await resolved
      if (!r) die(`${row.name}: the answer was sent but no resolution came back within 10s`)
      const left = r.unanswered?.length ? `; unanswered: ${r.unanswered.join(", ")}` : ""
      return console.log(`${row.name}: ${r.outcome}${left}`)
    }

    if (cmd === "wait") {
      const timeout = Number(option(args, "--timeout")[0] ?? 1800)
      const row = await resolve(rpc, args[0])
      const { sid, state } = await attach(rpc, row)
      if (stateOf(state) === "busy") {
        const why = await rpc.until(
          (m) =>
            m.sessionId !== sid ? undefined : m.type === "agent_settled" ? "idle" : m.type === "extension_ui_request" && m.method === "question" ? "question" : undefined,
          timeout * 1000,
        )
        if (!why) {
          console.log(`${row.name}: still busy after ${timeout}s`)
          process.exitCode = 2
          return
        }
      }
      return await printStatus(rpc, row)
    }

    die(`unknown command "${cmd}"\n\n${USAGE}`)
  } finally {
    rpc.close()
  }
}

// wt makes the worktree and its session (WT_SYNC: checked out before it
// returns; WT_DETACH: without switching you into it). omo is typed into that
// session's own fish so it gets the same login + direnv environment as any
// pane; the leading space keeps it out of fish history.
// With --stack, `wts add` makes the layer (and its session) on top of the stack
// root, which is itself a plain wt worktree, created here if it doesn't exist.
async function spawn(name: string, prompt: string, stack?: string, after?: string, needs: string[] = []) {
  if (!/^[a-z0-9][a-z0-9._-]*$/.test(name)) die(`invalid name "${name}": use lowercase kebab-case`)
  if (!process.env.TMUX) die("needs to run inside tmux")
  const p = project() ?? die("not in a git repo")
  for (const n of needs) if (!existsSync(pathOf(p, n))) die(`--needs ${n}: no such agent worktree`)
  pullTrunk(p.main)
  const wt = (n: string) => {
    const r = spawnSync("fish", ["-c", "set -x WT_SYNC 1; set -x WT_DETACH 1; wt $argv[1]", n], { encoding: "utf8" })
    if (r.status !== 0) die(`wt: ${(r.stderr || r.stdout).trim()}`)
  }
  let target: string
  if (stack) {
    const root = join(p.worktrees, stack)
    if (!existsSync(join(root, ".git"))) wt(stack)
    target = join(p.worktrees, ".stacks", stack, name)
    if (existsSync(target)) die(`layer ${stack}/${name} already exists; use agent talk`)
    const r = spawnSync("wts", ["add", name, ...(after ? ["--after", after] : [])], { cwd: root, encoding: "utf8" })
    if (r.status !== 0) die(`wts add: ${(r.stderr || r.stdout).trim()}`)
  } else {
    target = join(p.worktrees, name)
    if (existsSync(join(target, ".git"))) die(`worktree ${name} already exists; use agent talk`)
    wt(name)
  }
  const session = sessionAt(target) ?? die(`no tmux session was created for ${target}`)
  const pane = paneOf(session)
  const dir = join(process.env.TMPDIR ?? tmpdir(), "omo-agent")
  mkdirSync(dir, { recursive: true })
  const file = join(dir, `${session.replaceAll("/", "__")}-${Date.now()}.md`)
  writeFileSync(file, prompt)
  // Only spawned agents join the shared host (see agent.nix), in the same
  // agent dir as this CLI so it is the host this talks to.
  const dirEnv = process.env.OMO_CODING_AGENT_DIR ? ` OMO_CODING_AGENT_DIR='${process.env.OMO_CODING_AGENT_DIR}'` : ""
  // With --needs, the agent's own pane holds omo back until its dependencies
  // are done; it is the same CLI build that spawned it.
  const gate = needs.length ? `env${dirEnv} ${process.env.AGENT_CLI ?? "agent"} await '${needs.join(",")}' && ` : ""
  tmux(["send-keys", "-t", pane, "-l", ` ${gate}env OMO_ENABLE_SHARED_HOST=1${dirEnv} omo "$(cat '${file}')"`], "tmux send-keys")
  tmux(["send-keys", "-t", pane, "Enter"], "tmux send-keys")
  const path = tmux(["display-message", "-p", "-t", pane, "#{pane_current_path}"], "tmux")
  const label = stack ? `${stack}/${name}` : name
  if (needs.length) return console.log(`queued ${label}: starts when ${needs.join(", ")} finish; tmux ${session}, worktree ${path}`)
  // Report it once it is on the host with its prompt submitted, so an
  // `agent wait` right after sees it busy rather than not yet started.
  const deadline = Date.now() + 60_000
  while (Date.now() < deadline) {
    if (existsSync(SOCKET)) {
      const rpc = await Rpc.connect()
      const list = await rows(rpc, true).finally(() => rpc.close())
      const row = list.find((r) => r.cwd === realpathSync(path))
      if (row && messages(row.sessionPath, "user").length) return console.log(`started ${row.name}: tmux ${session}, worktree ${path}`)
    }
    await Bun.sleep(1000)
  }
  console.log(`started ${name} in tmux ${session} (worktree ${path}), but it has not joined the RPC host; use agent peek/open`)
}

// New agents branch off the main branch, so bring it up to origin first.
// Fast-forward only: local commits on it, or a dirty tree in the way, stop the
// spawn instead of being merged or rebased. When the main checkout is on
// another branch, the fetch moves the local main ref directly.
function pullTrunk(main: string) {
  const trunk = (git(main, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) ?? "origin/main").replace(/^origin\//, "")
  const run = (args: string[]) => {
    const r = spawnSync("git", ["-C", main, ...args], { encoding: "utf8" })
    if (r.status !== 0) die(`could not pull ${trunk} before spawning: ${(r.stderr || r.stdout).trim()}`)
  }
  if (git(main, ["branch", "--show-current"]) === trunk) {
    run(["fetch", "-q", "origin", trunk])
    run(["merge", "--ff-only", "-q", `origin/${trunk}`])
  } else run(["fetch", "-q", "origin", `${trunk}:${trunk}`])
}

// Agent name -> worktree: "main", "<name>" (wt) or "<root>/<layer>" (wts).
function pathOf(p: NonNullable<ReturnType<typeof project>>, name: string): string {
  if (name === "main") return p.main
  return name.includes("/") ? join(p.worktrees, ".stacks", name) : join(p.worktrees, name)
}

// Done, read from the world rather than the agent: idle with nothing asked,
// a clean worktree, and commits of its own (over its parent layer, or over the
// main checkout's branch). Your uncommitted edits after a takeover hold it.
async function doneOf(p: NonNullable<ReturnType<typeof project>>, names: string[]): Promise<Set<string>> {
  const done = new Set<string>()
  if (!existsSync(SOCKET)) return done
  const rpc = await Rpc.connect()
  try {
    const list = await rows(rpc, true)
    for (const name of names) {
      const path = pathOf(p, name)
      if (!existsSync(path)) continue
      const row = list.find((r) => r.cwd === realpathSync(path))
      if (!row || stateOf((await attach(rpc, row)).state) !== "idle") continue
      if (git(path, ["status", "--porcelain"]) !== "") continue
      const base = path.includes("/.stacks/") ? "@{upstream}" : git(p.main, ["branch", "--show-current"])
      if (Number(git(path, ["rev-list", "--count", `${base}..HEAD`]) ?? 0) > 0) done.add(name)
    }
  } finally {
    rpc.close()
  }
  return done
}

// Runs in a waiting agent's own pane. A local check every few seconds; no
// model is involved, so waiting costs nothing.
async function awaitDeps(deps: string[]) {
  const p = project() ?? die("not in a git repo")
  const pane = process.env.TMUX_PANE
  if (pane) spawnSync("tmux", ["set-option", "-p", "-t", pane, "@agent-needs", deps.join(",")])
  console.log(`waiting for ${deps.join(", ")} to finish (idle, clean, committed); ctrl+c to stop`)
  let left = deps
  while (left.length) {
    const done = await doneOf(p, left).catch(() => new Set<string>())
    for (const d of done) console.log(`${d} is done`)
    left = left.filter((d) => !done.has(d))
    if (left.length) await Bun.sleep(5000)
  }
  if (pane) spawnSync("tmux", ["set-option", "-p", "-u", "-t", pane, "@agent-needs"])
  // A layer made before its parent finished has no commits of its own yet, so
  // moving it onto the parent's finished work is a fast-forward.
  if (process.cwd().includes("/.stacks/")) {
    const r = spawnSync("git", ["merge", "--ff-only", "-q", "@{upstream}"], { encoding: "utf8" })
    if (r.status !== 0) die(`could not fast-forward onto the parent layer: ${(r.stderr || r.stdout).trim()}`)
  }
}

// Agents still held by `agent await`, as [name, needs].
function waiting(): [string, string][] {
  const p = project()
  if (!p || !process.env.TMUX) return []
  const r = spawnSync("tmux", ["list-panes", "-a", "-F", "#{pane_current_path}\t#{@agent-needs}"], { encoding: "utf8" })
  if (r.status !== 0) return []
  return r.stdout
    .split("\n")
    .map((l) => l.split("\t"))
    .filter(([path, needs]) => needs && existsSync(path))
    .flatMap(([path, needs]) => {
      const name = nameOf(realpathSync(path), p)
      return name ? [[name, needs] as [string, string]] : []
    })
}

main().catch((e) => die(e instanceof Error ? e.message : String(e)))
