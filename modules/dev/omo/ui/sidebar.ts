// opencode-style right sidebar. omo's fullscreen renderer lays out a flex
// tree (TuiAltScreen.layoutRoot); wrapping that root in an HStack gives the
// sidebar a real column, so transcript, editor and footer reflow beside it
// instead of being painted over. layoutRoot/setLayoutRoot are omo internals,
// not extension API: only this file and tools.ts touch omo internals.
import { spawnSync } from "node:child_process"
import { HStack, VStack, visibleWidth } from "@earendil-works/pi-tui"
import { BACKDROP } from "./sessions.ts"
import { type Ctx, contextUsage, type Entry, homePath, paint, sessionCost, type Theme } from "./stats.ts"

const WIDTH = 40
const MIN_TERMINAL_WIDTH = 100
const MARGIN_LEFT = 2
const MARGIN_X = 2
const MARGIN_Y = 1
const BG = "userMessageBg"
const VERSION = process.execPath.match(/binary-runtime\/([^/]+)\//)?.[1] ?? ""
const INNER = Symbol.for("omo-ui-sidebar.inner")
const ORIGINAL_SELECTION = Symbol.for("omo-ui-sidebar.applySelection")

type Component = { render(width: number): string[]; invalidate(): void }
type LayoutTui = {
  layoutRoot?: Component
  setLayoutRoot?(root: Component | undefined): void
  requestRender(): void
  terminal: { rows: number; columns: number }
  applySelection?(screen: string[], layout?: unknown): string[]
}
type UiCtx = Ctx & {
  ui: { setWidget(key: string, factory: ((tui: LayoutTui, theme: Theme) => Component) | undefined): void }
}
type Pi = {
  on(event: string, handler: (event: unknown, ctx: UiCtx) => void): void
  getSessionName(): string | undefined
  registerCommand(name: string, options: { description: string; handler: (args: string, ctx: UiCtx) => Promise<void> }): void
}

type State = {
  title: string
  sessionId: string
  tokens: string
  percent: string
  cost: string
  files: string[]
  location: string
}

const EDIT_TOOLS = new Set(["edit", "write"])

function firstUserText(entries: Entry[]): string {
  for (const e of entries) {
    const m = e.message
    if (e.type !== "message" || m?.role !== "user") continue
    const text = typeof m.content === "string" ? m.content : m.content?.find((b) => b.type === "text")?.text
    if (typeof text === "string" && text.trim()) return text.trim().split("\n")[0]
  }
  return "New session"
}

const ESCAPE = /^(?:\x1b\[[0-9;:?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\))/

function resetAt(line: string, column: number): string {
  let col = 0
  let i = 0
  while (i < line.length) {
    const escape = line[i] === "\x1b" ? ESCAPE.exec(line.slice(i)) : null
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

function gitBranch(cwd: string): string {
  const r = spawnSync("git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8" })
  return r.status === 0 ? r.stdout.trim() : ""
}

function collect(pi: Pi, ctx: Ctx, branch: string): State {
  const entries = ctx.sessionManager.getBranch()
  const files = new Set<string>()
  for (const e of entries) {
    const m = e.message
    if (e.type !== "message" || m?.role !== "assistant" || !Array.isArray(m.content)) continue
    for (const b of m.content) {
      if (b.type === "toolCall" && EDIT_TOOLS.has(b.name ?? "") && b.arguments?.path) files.add(b.arguments.path)
    }
  }
  const { tokens, percent } = contextUsage(ctx)
  const cwdPrefix = ctx.cwd.endsWith("/") ? ctx.cwd : `${ctx.cwd}/`
  return {
    title: pi.getSessionName() ?? firstUserText(entries),
    sessionId: ctx.sessionManager.getSessionId(),
    tokens: tokens === undefined ? "?" : tokens.toLocaleString("en-US"),
    percent: percent === undefined ? "?" : `${Math.round(percent)}%`,
    cost: `$${sessionCost(entries).toFixed(2)}`,
    files: [...files].map((f) => (f.startsWith(cwdPrefix) ? f.slice(cwdPrefix.length) : f)),
    location: `${homePath(ctx.cwd)}${branch ? `:${branch}` : ""}`,
  }
}

function renderPanel(state: State, theme: Theme, width: number, rows: number): string[] {
  const body: string[] = []
  const line = (text = "") => body.push(text)
  const muted = (text: string) => line(theme.fg("muted", text))

  line()
  line(theme.bold(state.title))
  muted(state.sessionId)
  line()
  line(theme.bold("Context"))
  muted(`${state.tokens} tokens`)
  muted(`${state.percent} used`)
  muted(`${state.cost} spent`)
  if (state.files.length > 0) {
    line()
    line(theme.bold("Modified Files"))
    for (const f of state.files) muted(f)
  }

  const footer = [state.location, "", `${theme.fg("success", "•")} ${theme.bold("OmO")} ${theme.fg("muted", VERSION)}`, ""]
  const filler = Math.max(1, rows - body.length - footer.length)
  return [...body, ...Array(filler).fill(""), ...footer].map((text) => paint(theme, BG, text ? `  ${text}` : "", width))
}

export default function sidebar(pi: Pi) {
  let visible = true
  let state: State | undefined
  let branch = ""
  let theme: Theme | undefined
  let tui: LayoutTui | undefined
  let root: Component | undefined
  const guarded = new WeakSet<LayoutTui>()

  const panel: Component = {
    render: (width) => (state && theme && tui ? renderPanel(state, theme, width, tui.terminal.rows) : []),
    invalidate() {},
  }
  // omo's layout pastes columns side by side without resetting SGR state, so
  // a transcript row that ends mid-background (tool blocks) would bleed into
  // whatever follows. Margins reset every row.
  const blank: Component = {
    render: (width) => Array.from({ length: tui?.terminal.rows ?? 0 }, () => `\x1b[0m${" ".repeat(width)}`),
    invalidate() {},
  }

  const refresh = (ctx: Ctx) => {
    state = collect(pi, ctx, branch)
    tui?.requestRender()
  }

  // Regular (non-fullscreen) mode has no layout root; the sidebar is a no-op there.
  // /new and /reload re-run session_start (and /reload a fresh copy of this
  // module), so the tui's layout root may already be a previous sidebar's
  // wrapper. The wrapper records omo's own root under a global symbol, which
  // survives module reloads; unwrap it before wrapping again.
  const mount = (t: LayoutTui, th: Theme) => {
    tui = t
    theme = th
    const current = t.layoutRoot as (Component & { [INNER]?: Component }) | undefined
    if (!t.setLayoutRoot || !current || current === root) return
    const inner = current[INNER] ?? current
    // A bottom margin under the main column only; the panel spans full height.
    const main = new VStack([
      { component: inner, basis: 0, grow: 1 },
      { component: blank, basis: MARGIN_Y, shrink: 0 },
    ])
    root = Object.assign(
      new HStack([
        { component: blank, basis: MARGIN_LEFT, shrink: 0 },
        { component: main, basis: 0, grow: 1 },
        { component: blank, basis: MARGIN_X, shrink: 0 },
        { component: panel, basis: WIDTH, shrink: 0, visible: (vp: { width: number }) => visible && vp.width >= MIN_TERMINAL_WIDTH },
      ]),
      { [INNER]: inner },
    ) as unknown as Component
    t.setLayoutRoot(root)
    guardSelection(t)
  }

  // omo's selection splits each row at the transcript's right edge and, when
  // rebuilding the rest of the row, re-emits the transcript's last colours
  // after any reset already there (sliceWithWidth's pendingAnsi), so the
  // first margin cell picks up tool-block backgrounds while text is
  // selected. Re-reset at that column after omo's pass.
  // The unwrapped method is kept on the tui under a global symbol so a
  // reloaded copy of this module replaces the guard instead of stacking one.
  const guardSelection = (t: LayoutTui & { [ORIGINAL_SELECTION]?: LayoutTui["applySelection"] }) => {
    const original = (t[ORIGINAL_SELECTION] ??= t.applySelection)
    if (!original || guarded.has(t)) return
    guarded.add(t)
    t.applySelection = function (this: LayoutTui, screen: string[], layout?: unknown) {
      const columns = t.terminal.columns
      const panelShown = visible && columns >= MIN_TERMINAL_WIDTH
      const edge = columns - MARGIN_X - (panelShown ? WIDTH : 0)
      const lines = original.call(this, screen, layout)
      return (globalThis as { [BACKDROP]?: boolean })[BACKDROP] ? lines : lines.map((line) => resetAt(line, edge))
    }
  }

  pi.on("session_start", (_e, ctx) => {
    branch = gitBranch(ctx.cwd)
    refresh(ctx)
    ctx.ui.setWidget("ui-sidebar-mount", (t, th) => {
      mount(t, th)
      return { render: () => [], invalidate() {} }
    })
  })
  for (const event of ["turn_end", "tool_result", "model_select", "session_info_changed"]) {
    pi.on(event, (_e, ctx) => refresh(ctx))
  }
  pi.on("agent_settled", (_e, ctx) => {
    branch = gitBranch(ctx.cwd)
    refresh(ctx)
  })

  pi.registerCommand("sidebar", {
    description: "Toggle the right sidebar",
    handler: async (_args, ctx) => {
      visible = !visible
      refresh(ctx)
    },
  })
}
