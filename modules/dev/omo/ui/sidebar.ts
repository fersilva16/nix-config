// opencode-style right sidebar. omo's fullscreen renderer lays out a flex
// tree; wrapping its root in an HStack (core/host.ts wrapLayout) gives the
// sidebar a real column, so transcript, editor and footer reflow beside it
// instead of being painted over. Its content comes from core/store.ts.
//
// While the sidebar is shown it also takes over omo's transcript notices
// (status lines, warnings, notice boxes, the update notice, the optimized
// prompt header) and the todo and nested AGENTS.md widgets above the prompt.
// Turn errors stay in the transcript.
import { execFile } from "node:child_process"
import { HStack, Key, matchesKey, truncateToWidth, VStack, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui"
import { type GitState, git, type Pr, startGit } from "./core/git.ts"
import {
  afterSelection,
  isModalFrame,
  onHeader,
  onNotice,
  onTui,
  onUpdate,
  onWidget,
  onWidgetContent,
  requestRender,
  type WidgetContent,
  wrapLayout,
} from "./core/host.ts"
import { type Account, limits, startLimits } from "./core/limits.ts"
import { modalFrame, openModal } from "./core/modal.ts"
import { refresh, refreshLive, type Snapshot, store, type TodoPhase } from "./core/store.ts"
import { ESCAPE_AT_START, homePath, paint, spread, stripAnsi } from "./core/style.ts"
import type { Component, Ctx, Theme, Tui } from "./core/types.ts"

const WIDTH = 40
const MIN_TERMINAL_WIDTH = 100
const MARGIN_LEFT = 2
const MARGIN_X = 2
const MARGIN_Y = 1
const PAD = 2
const BG = "userMessageBg"
const VERSION = process.execPath.match(/binary-runtime\/([^/]+)\//)?.[1] ?? ""
const MAX_NOTICES = 50
// omo's todo backstop gives the model this many reminders before it stops.
const TODO_REMINDERS = 2
const TODO_STOPPED = /^Agent stopped with \d+ open todo tasks/
const OPTIMIZED = /^Optimized system prompt applied: /
const NESTED_WIDGET = "ext:nested-agents:widget"
const MARKS: Record<string, [token: string, mark: string]> = {
  completed: ["success", "✓"],
  in_progress: ["accent", "•"],
  pending: ["muted", "○"],
  abandoned: ["muted", "✗"],
}

type ModalCtx = Parameters<typeof openModal>[0]
type SessionCtx = Ctx & ModalCtx & { ui: { setWidget(key: string, content: WidgetContent | undefined): void } }
type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: SessionCtx) => void): void
  registerCommand(name: string, options: { description: string; handler: (args: string, ctx: SessionCtx) => Promise<void> }): void
}
type Mouse = { type: string; button?: string; y: number }

function resetAt(line: string, column: number): string {
  let col = 0
  let i = 0
  while (i < line.length) {
    const escape = line[i] === "\x1b" ? ESCAPE_AT_START.exec(line.slice(i)) : null
    if (escape) {
      i += escape[0].length
      continue
    }
    if (col === column) return `${line.slice(0, i)}\x1b[0m${line.slice(i)}`
    const char = String.fromCodePoint(line.codePointAt(i) ?? 32)
    col += visibleWidth(char)
    i += char.length
  }
  return line
}

const isOpen = (status: string) => status === "pending" || status === "in_progress"

// The phase holding the next actionable task, as omo's todo widget picks it.
function activePhase(phases: TodoPhase[]): TodoPhase | undefined {
  const tasks = phases.flatMap((p) => p.tasks)
  const next = tasks.find((t) => t.status === "in_progress") ?? tasks.find((t) => t.status === "pending")
  return next && phases.find((p) => p.tasks.includes(next))
}

function todoSection(phases: TodoPhase[], theme: Theme, inner: number): string[] {
  const active = activePhase(phases)
  if (!active) return []
  const owed = store.todoOwed
  const marker = !owed
    ? ""
    : owed.reason === "capped"
      ? theme.fg("warning", `  stopped · ${owed.openTasks} open`)
      : theme.fg("muted", `  reminded ${owed.chainCount}/${TODO_REMINDERS}`)
  const lines = ["", `${theme.bold("Todo")}${marker}`]
  for (const phase of phases) {
    const progress = `${phase.tasks.filter((t) => !isOpen(t.status)).length}/${phase.tasks.length}`
    if (phase !== active) {
      lines.push(theme.fg("muted", `${phase.name} ${progress}`))
      continue
    }
    lines.push(`${phase.name} ${theme.fg("muted", progress)}`)
    for (const task of phase.tasks) {
      const [token, mark] = MARKS[task.status] ?? MARKS.pending
      const text = task.status === "in_progress" ? task.content : theme.fg("muted", task.content)
      wrapTextWithAnsi(text, inner - 2).forEach((l: string, i: number) => lines.push(`${i === 0 ? theme.fg(token, mark) : " "} ${l}`))
    }
  }
  return lines
}

// Commits behind the default branch from which the line turns to a warning:
// testing the branch then no longer tests what has landed.
const FAR_BEHIND = 20
// Failing checks listed by name; past this they are counted.
const MAX_FAILING = 3

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`

// Cut from the left: a worktree's own directory is at the end of its path.
const fitPath = (path: string, width: number) => (path.length <= width ? path : `…${path.slice(path.length - width + 1)}`)

// The repo and its PR at a glance. A line that would only say "nothing to
// report" (up to date, clean tree, no review yet on a draft) is left out.
// Every PR row opens the PR on click (its rows are in `links`).
function gitSection(
  state: GitState | undefined,
  pr: Pr | undefined,
  theme: Theme,
  inner: number,
): { lines: string[]; links: Map<number, string> } {
  const links = new Map<number, string>()
  if (!state) return { lines: [], links }
  const muted = (text: string) => theme.fg("muted", text)
  const lines = ["", theme.bold("Git"), truncateToWidth(state.branch || `detached at ${state.head}`, inner, "…")]
  const { behind, ahead } = state
  if (behind > 0 || ahead > 0) {
    // On the default branch itself the comparison is with its remote copy.
    const target = state.branch === state.base ? `origin/${state.base}` : state.base
    const text =
      behind > 0 && ahead > 0
        ? `${behind} behind, ${ahead} ahead of ${target}`
        : behind > 0
          ? `${behind} behind ${target}`
          : `${ahead} ahead of ${target}`
    lines.push(theme.fg(behind >= FAR_BEHIND ? "warning" : "muted", text))
  }
  const tree = [
    state.conflicted > 0 ? theme.fg("error", `${state.conflicted} conflicted`) : "",
    state.uncommitted > 0 ? muted(`${state.uncommitted} uncommitted`) : "",
    state.untracked > 0 ? muted(`${state.untracked} untracked`) : "",
  ].filter(Boolean)
  if (tree.length > 0) lines.push(tree.join(muted(", ")))
  lines.push(muted(fitPath(homePath(state.cwd), inner)))
  if (!pr) return { lines, links }

  const first = lines.length + 1
  const merged = pr.state === "MERGED"
  const status = merged ? "merged" : pr.draft ? "draft" : "open"
  lines.push("", spread(theme.bold("Pull Request"), muted(`#${pr.number} ${status}`), inner))
  if (!merged) {
    const ok = (text: string) => `${theme.fg("success", "✓")} ${muted(text)}`
    if (pr.checks === "fail") {
      for (const name of pr.failing.slice(0, MAX_FAILING)) lines.push(theme.fg("error", truncateToWidth(`✗ ${name}`, inner, "…")))
      if (pr.failing.length > MAX_FAILING) lines.push(theme.fg("error", `  ${pr.failing.length - MAX_FAILING} more failing`))
    } else if (pr.checks === "pending") lines.push(`${theme.fg("accent", "•")} ${muted(`${plural(pr.running, "check")} running`)}`)
    else if (pr.checks === "pass") lines.push(ok("checks passed"))
    if (pr.unresolved > 0) lines.push(theme.fg("warning", plural(pr.unresolved, "unresolved comment")))
    if (pr.review === "APPROVED") lines.push(ok("approved"))
    else if (pr.review === "CHANGES_REQUESTED") lines.push(theme.fg("warning", "changes requested"))
    else if (pr.review === "REVIEW_REQUIRED" && !pr.draft) lines.push(muted("review required"))
    if (pr.conflict) lines.push(theme.fg("error", truncateToWidth(`✗ conflicts with ${pr.base}`, inner, "…")))
  }
  for (let row = first; row < lines.length; row++) links.set(row, pr.url)
  return { lines, links }
}

// A failure lands in the sidebar's warnings: a click has nowhere else to say.
function openUrl(url: string): void {
  execFile(process.platform === "darwin" ? "open" : "xdg-open", [url], (error: Error | null) => {
    if (!error) return
    store.notices = [...store.notices, { kind: "warning", text: `Could not open ${url}: ${error.message}` }]
    requestRender()
  })
}

// Brand colour per provider, as raw truecolour: the theme has no token for
// them. Claude's orange and OpenAI's green.
const LIMIT_COLORS: Record<string, string> = {
  claude: "217;119;87",
  codex: "16;163;127",
}

// Nerd Font glyph per provider, drawn in its brand colour. An empty slot falls
// back to a dot.
// Pooled providers the user expanded with a click. Per process, like /sidebar.
const openLimits = new Set<string>()

const LIMIT_ICONS: Record<string, string> = {
  claude: " ",
  codex: " ",
}

// antiburn's pace: the burn rate over the rate that would land exactly on 100%
// at reset, in its bands. The rate is the window's average so far rather than
// antiburn's last two hours of samples, so it needs no history, and above 1.0
// means exactly "runs out before reset". Skipped for the first 5% of a
// window, where a handful of requests reads as a wild ratio.
const PACE: [below: number, word: string, token: string][] = [
  [0.8, "comfortable", "success"],
  [1.1, "on pace", "muted"],
  [1.5, "running hot", "warning"],
  [Number.POSITIVE_INFINITY, "at risk", "error"],
]

function pace(w: Account["windows"][number], now: number) {
  if (!w.seconds || !w.resetsAt) return undefined
  const elapsed = w.seconds - (w.resetsAt - now) / 1000
  if (elapsed < w.seconds * 0.05) return undefined
  const expected = Math.min(1, elapsed / w.seconds)
  const [, word, token] = PACE.find(([below]) => w.percent / (expected * 100) < below) ?? PACE[PACE.length - 1]
  const out = w.percent > 0 && w.percent < 100 ? now + ((100 - w.percent) / w.percent) * elapsed * 1000 : undefined
  return { expected, word, token, out: out !== undefined && out < w.resetsAt ? out : undefined }
}

// Providers with several accounts (both Claude logins) pool them into one
// bucket: each window averages the members' usage, and their reset times too,
// so pace sees the average share of the window elapsed. omo spreads load across
// the logins, so the pool is what is actually left. Clicking a pooled title
// (its row is in `toggles`) swaps the pool for one section per account.
//
// Green while there is headroom, warning from half spent, error from 90%. The
// hottest window's reset joins the header from 75%.
function limitsSection(
  accounts: Account[],
  theme: Theme,
  inner: number,
  open: Set<string>,
): { lines: string[]; toggles: Map<number, string> } {
  type Windows = Account["windows"]
  const now = Date.now()
  const tone = (p: number) => (p >= 90 ? "error" : p >= 50 ? "warning" : "success")
  const when = (at: number) =>
    at - now < 86_400_000
      ? new Date(at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })
      : new Date(at).toLocaleDateString("en-US", { weekday: "short" })
  const live = (a: Account) => a.windows.filter((w) => w.resetsAt === undefined || w.resetsAt > now)
  const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length
  const pool = (members: Account[]): Windows =>
    [...new Set(members.flatMap((m) => live(m).map((w) => w.label)))].map((label) => {
      const ws = members.flatMap((m) => live(m).filter((w) => w.label === label))
      const resets = ws.flatMap((w) => (w.resetsAt ? [w.resetsAt] : []))
      return { label, percent: avg(ws.map((w) => w.percent)), resetsAt: resets.length > 0 ? avg(resets) : undefined, seconds: ws[0].seconds }
    })
  const status = (errors: string[], windows: Windows) => {
    const hottest = windows.reduce<Windows[number] | undefined>((h, w) => (!h || w.percent > h.percent ? w : h), undefined)
    return errors.length > 0
      ? theme.fg("warning", windows.length > 0 ? "stale" : errors[0])
      : hottest && hottest.percent >= 75 && hottest.resetsAt
        ? theme.fg("muted", `↻ ${when(hottest.resetsAt)}`)
        : ""
  }
  // spread() would measure the left side itself, and visibleWidth takes a Nerd
  // Font glyph for two cells where the terminal draws one; callers pass it.
  const header = (left: string, width: number, right: string) =>
    right ? `${left}${" ".repeat(Math.max(1, inner - width - visibleWidth(right)))}${right}` : left

  // A cache written before accounts carried a provider falls back to the name
  // until the next fetch rewrites it.
  const groups = new Map<string, Account[]>()
  for (const a of accounts) groups.set(a.provider ?? a.name, [...(groups.get(a.provider ?? a.name) ?? []), a])

  const lines: string[] = []
  const toggles = new Map<number, string>()
  for (const [provider, members] of groups) {
    if (lines.length > 0) lines.push("")
    const pooled = members.length > 1
    const expanded = pooled && open.has(provider)
    const rgb = LIMIT_COLORS[provider]
    const glyph = LIMIT_ICONS[provider] || "●"
    const icon = rgb ? `\x1b[38;2;${rgb}m${glyph}\x1b[39m` : glyph
    const fold = pooled ? theme.fg("muted", expanded ? " ▾" : " ▸") : ""
    // No separator: a full cell reads as too wide a gap, and a terminal has
    // nothing narrower. The glyph's own side bearing is the gap.
    const title = `${icon}${provider[0].toUpperCase()}${provider.slice(1)}${fold}`
    const titleWidth = 1 + provider.length + (pooled ? 2 : 0)
    // +2 for the blank line and heading prepended below.
    if (pooled) toggles.set(lines.length + 2, provider)
    if (expanded) {
      lines.push(title)
      for (const m of members) {
        lines.push(header(`  ${theme.fg("muted", m.name)}`, m.name.length + 2, status(m.error ? [m.error] : [], live(m))))
        bars(live(m), 4)
      }
      continue
    }
    const windows = pooled ? pool(members) : live(members[0])
    lines.push(header(title, titleWidth, status(members.flatMap((m) => (m.error ? [m.error] : [])), windows)))
    bars(windows, 2)
  }
  return { lines: lines.length > 0 ? ["", theme.bold("Limits"), ...lines] : [], toggles }

  function bars(windows: Windows, indent: number): void {
    const pad = " ".repeat(indent)
    for (const w of windows) {
      const percent = Math.min(100, Math.max(0, w.percent))
      const label = `${Math.round(w.percent)}%`.padStart(4)
      // indent + "5h " + bar + " " + label
      const bar = inner - indent - 2 - w.label.length - label.length
      const filled = Math.round((percent / 100) * bar)
      const seg = (from: number, to: number) =>
        theme.fg(tone(percent), "━".repeat(Math.max(0, Math.min(to, filled) - from))) +
        theme.fg("borderMuted", "─".repeat(Math.max(0, to - Math.max(from, filled))))
      const p = pace(w, now)
      // ❙ marks where usage would be at an even burn, in the pace band's
      // colour: fill past it is ahead of pace.
      const mark = p ? Math.min(bar - 1, Math.round(p.expected * bar)) : -1
      const track = p ? `${seg(0, mark)}${theme.fg(p.token, "❙")}${seg(mark + 1, bar)}` : seg(0, bar)
      lines.push(`${pad}${theme.fg("muted", w.label)} ${track} ${theme.fg(percent >= 50 ? tone(percent) : "muted", label)}`)
      // Comfortable and on pace need no words; the marker already says so.
      if (p && (p.token === "warning" || p.token === "error")) {
        const under = " ".repeat(indent + w.label.length + 1)
        const out = p.out ? theme.fg(p.token, `out ${when(p.out)}`) : ""
        lines.push(spread(`${under}${theme.fg(p.token, p.word)}`, out, inner))
      }
    }
  }
}

function renderPanel(
  state: Snapshot,
  theme: Theme,
  width: number,
  rows: number,
): { lines: string[]; warningsRow: number | undefined; toggles: Map<number, string>; links: Map<number, string> } {
  const body: string[] = []
  const line = (text = "") => body.push(text)
  const muted = (text: string) => line(theme.fg("muted", text))

  line()
  line(theme.bold(state.title))
  muted(state.sessionId)
  line()
  line(`${theme.bold("Context")}${store.promptOptimized ? theme.fg("muted", " (Optimized)") : ""}`)
  muted(`${state.tokens === undefined ? "?" : state.tokens.toLocaleString("en-US")} tokens`)
  muted(`${state.percent === undefined ? "?" : `${Math.round(state.percent)}%`} used`)
  muted(`$${state.cost.toFixed(2)} spent`)
  const limitsAt = body.length
  const limitRows = limitsSection(limits.accounts, theme, width - 2 * PAD, openLimits)
  body.push(...limitRows.lines)
  body.push(...todoSection(state.todos, theme, width - 2 * PAD))
  if (store.nestedContext.length > 0) {
    line()
    line(theme.bold("Nested Context"))
    for (const f of store.nestedContext) line(f.truncated ? theme.fg("warning", `${f.path} (truncated)`) : theme.fg("muted", f.path))
  }

  const notices = store.notices
  const alert = notices.some((n) => n.kind !== "status")
  const warnings = notices.length > 0 ? [theme.fg(alert ? "warning" : "muted", `warnings (${notices.length})`)] : []
  const update = store.update ? theme.fg("warning", ` (Update Available ${store.update})`) : ""
  // The Git section sits at the bottom, above the warnings, where the
  // cwd:branch footer used to be. The filler is the gap above its heading, so
  // its own leading blank goes; a blank keeps the warnings off its last line.
  const gitRows = gitSection(git.state, git.pr, theme, width - 2 * PAD)
  const gitLines = gitRows.lines.slice(1)
  const gap = gitLines.length > 0 && warnings.length > 0 ? [""] : []
  const footer = [...gitLines, ...gap, ...warnings, "", `${theme.fg("success", "•")} ${theme.bold("OmO")} ${theme.fg("muted", VERSION)}${update}`, ""]
  const filler = Math.max(1, rows - body.length - footer.length)
  const footerAt = body.length + filler
  return {
    lines: [...body, ...Array(filler).fill(""), ...footer].map((text) => paint(theme, BG, text ? `${" ".repeat(PAD)}${text}` : "", width)),
    warningsRow: warnings.length > 0 ? footerAt + gitLines.length + gap.length : undefined,
    toggles: new Map([...limitRows.toggles].map(([row, provider]) => [row + limitsAt, provider])),
    links: new Map([...gitRows.links].map(([row, url]) => [row - 1 + footerAt, url])),
  }
}

function showNotices(ctx: ModalCtx): Promise<void> {
  return openModal<void>(ctx, (tui, theme, done) => ({
    render(width) {
      const f = modalFrame(theme, width)
      const body = store.notices.toReversed().flatMap((n) => {
        const token = n.kind === "status" ? "muted" : n.kind
        const [first = "", ...rest] = [...(n.title ? [n.title] : []), ...n.text.split("\n")]
        return [
          ...wrapTextWithAnsi(theme.fg(token, first), f.inner),
          ...rest.flatMap((l) => wrapTextWithAnsi(l, f.inner)),
          "",
        ]
      })
      const height = Math.max(3, Math.floor(tui.terminal.rows * 0.75) - 6)
      const shown = body.length > 0 ? body.slice(0, Math.min(height, body.length - 1)) : [theme.fg("muted", "No warnings")]
      return [
        f.line(),
        f.header("Warnings"),
        f.line(),
        ...shown.map((l) => f.line(l)),
        f.line(),
        f.line(f.hints([["clear", "c"]])),
        f.line(),
      ]
    },
    invalidate() {},
    handleInput(data) {
      if (matchesKey(data, Key.escape)) return done()
      if (data === "c") {
        store.notices = []
        requestRender()
        done()
      }
    },
  }))
}

export default function sidebar(pi: Pi) {
  let visible = true
  let fullscreen = false
  let theme: Theme | undefined
  let tui: Tui | undefined
  let ctx: SessionCtx | undefined
  let warningsRow: number | undefined
  let toggles = new Map<number, string>()
  let links = new Map<number, string>()

  // Startup notices (config diagnostics) arrive before the sidebar mounts;
  // they are taken on the assumption that the tui will be fullscreen.
  const shown = () => (tui ? fullscreen : true) && visible && (tui?.terminal.columns ?? process.stdout.columns ?? 0) >= MIN_TERMINAL_WIDTH

  const panel = {
    render: (width: number) => {
      if (!store.snapshot || !theme || !tui) return []
      const out = renderPanel(store.snapshot, theme, width, tui.terminal.rows)
      warningsRow = out.warningsRow
      toggles = out.toggles
      links = out.links
      return out.lines
    },
    invalidate() {},
    handleMouse: (event: Mouse) => {
      if (event.type !== "press" || event.button !== "left") return
      const provider = toggles.get(event.y)
      if (provider) {
        if (!openLimits.delete(provider)) openLimits.add(provider)
        requestRender()
        return { handled: true }
      }
      const url = links.get(event.y)
      if (url) {
        openUrl(url)
        return { handled: true }
      }
      if (event.y !== warningsRow || !ctx) return
      void showNotices(ctx)
      return { handled: true }
    },
  } as unknown as Component
  // omo's layout pastes columns side by side without resetting SGR state, so
  // a transcript row that ends mid-background (tool blocks) would bleed into
  // whatever follows. Margins reset every row.
  const blank: Component = {
    render: (width) => Array.from({ length: tui?.terminal.rows ?? 0 }, () => `\x1b[0m${" ".repeat(width)}`),
    invalidate() {},
  }

  onNotice((notice) => {
    // The todo section's marker says the agent stopped; omo's model-side
    // reminder is a hidden message and is not affected.
    if (TODO_STOPPED.test(notice.text)) return true
    if (!shown()) return false
    const last = store.notices.at(-1)
    if (last?.kind !== notice.kind || last.text !== notice.text || last.title !== notice.title) {
      store.notices = [...store.notices, notice].slice(-MAX_NOTICES)
    }
    requestRender()
    return true
  })
  onUpdate((version) => {
    store.update = version
    requestRender()
    return shown()
  })
  // omo sets this header on session start, before the sidebar mounts, so it
  // is always taken; the Context heading shows it.
  onHeader((text) => {
    store.promptOptimized = text !== undefined && OPTIMIZED.test(text)
    return store.promptOptimized
  })
  onWidget("todo-sidebar", () => {
    refreshLive()
    return shown()
  })
  // omo's /nested-agents widget: ["Nested Context:", "  path",
  // "  path (truncated)", ...]. Its last content is re-set on /sidebar, so it
  // moves between omo's spot above the prompt and the panel.
  let nested: WidgetContent | undefined
  onWidgetContent(NESTED_WIDGET, (content) => {
    nested = content
    const files = Array.isArray(content) ? content.slice(1).map((l) => stripAnsi(l).trim()) : []
    store.nestedContext = files.map((f) => ({ path: f.replace(/ \(truncated\)$/, ""), truncated: f.endsWith(" (truncated)") }))
    requestRender()
    return Array.isArray(content) && shown() ? undefined : content
  })

  onTui((t, th) => {
    tui = t
    theme = th
    // Polls only where there is a screen to show it: headless workers never
    // mount a tui.
    startLimits()
    startGit()
    fullscreen = wrapLayout(t, (inner) => {
      // A bottom margin under the main column only; the panel spans full height.
      const main = new VStack([
        { component: inner, basis: 0, grow: 1 },
        { component: blank, basis: MARGIN_Y, shrink: 0 },
      ])
      return new HStack([
        { component: blank, basis: MARGIN_LEFT, shrink: 0 },
        { component: main, basis: 0, grow: 1 },
        { component: blank, basis: MARGIN_X, shrink: 0 },
        { component: panel, basis: WIDTH, shrink: 0, visible: (vp: { width: number }) => visible && vp.width >= MIN_TERMINAL_WIDTH },
      ]) as unknown as Component
    })
    if (!fullscreen) return
    // omo's selection splits each row at the transcript's right edge and, when
    // rebuilding the rest of the row, re-emits the transcript's last colours
    // after any reset already there (sliceWithWidth's pendingAnsi), so the
    // first margin cell picks up tool-block backgrounds while text is
    // selected. Re-reset at that column after omo's pass.
    afterSelection(t, (lines) => {
      if (isModalFrame()) return lines
      const columns = t.terminal.columns
      const edge = columns - MARGIN_X - (visible && columns >= MIN_TERMINAL_WIDTH ? WIDTH : 0)
      return lines.map((line) => resetAt(line, edge))
    })
  })

  // omo's todo extension sets its widget on session start, before the sidebar
  // mounts; clear it once the sidebar is known to be shown.
  pi.on("session_start", (_e, c) => {
    ctx = c
    if (shown()) c.ui.setWidget("todo-sidebar", undefined)
  })

  pi.registerCommand("sidebar", {
    description: "Toggle the right sidebar",
    handler: async (_args, c) => {
      visible = !visible
      if (shown()) c.ui.setWidget("todo-sidebar", undefined)
      c.ui.setWidget(NESTED_WIDGET, nested)
      refresh(c)
    },
  })
}
