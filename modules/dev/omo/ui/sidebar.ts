// opencode-style right sidebar. omo's fullscreen renderer lays out a flex
// tree; wrapping its root in an HStack (core/host.ts wrapLayout) gives the
// sidebar a real column, so transcript, editor and footer reflow beside it
// instead of being painted over. Its content comes from core/store.ts.
//
// While the sidebar is shown it also takes over omo's transcript notices
// (status lines, warnings, notice boxes, the update notice, the optimized
// prompt header) and the todo widget above the prompt. Turn errors stay in
// the transcript.
import { HStack, Key, matchesKey, VStack, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui"
import { afterSelection, isModalFrame, onHeader, onNotice, onTui, onUpdate, onWidget, requestRender, wrapLayout } from "./core/host.ts"
import { modalFrame, openModal } from "./core/modal.ts"
import { refresh, refreshLive, type Snapshot, store, type TodoPhase } from "./core/store.ts"
import { ESCAPE_AT_START, homePath, paint } from "./core/style.ts"
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
const MARKS: Record<string, [token: string, mark: string]> = {
  completed: ["success", "✓"],
  in_progress: ["accent", "•"],
  pending: ["muted", "○"],
  abandoned: ["muted", "✗"],
}

type ModalCtx = Parameters<typeof openModal>[0]
type SessionCtx = Ctx & ModalCtx & { ui: { setWidget(key: string, content: undefined): void } }
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

function renderPanel(state: Snapshot, theme: Theme, width: number, rows: number): { lines: string[]; warningsRow: number | undefined } {
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
  body.push(...todoSection(state.todos, theme, width - 2 * PAD))
  if (state.files.length > 0) {
    line()
    line(theme.bold("Modified Files"))
    for (const f of state.files) muted(f)
  }

  const notices = store.notices
  const alert = notices.some((n) => n.kind !== "status")
  const warnings = notices.length > 0 ? [theme.fg(alert ? "warning" : "muted", `warnings (${notices.length})`)] : []
  const location = `${homePath(state.cwd)}${state.branch ? `:${state.branch}` : ""}`
  const update = store.update ? theme.fg("warning", ` (Update Available ${store.update})`) : ""
  const footer = [...warnings, location, "", `${theme.fg("success", "•")} ${theme.bold("OmO")} ${theme.fg("muted", VERSION)}${update}`, ""]
  const filler = Math.max(1, rows - body.length - footer.length)
  return {
    lines: [...body, ...Array(filler).fill(""), ...footer].map((text) => paint(theme, BG, text ? `${" ".repeat(PAD)}${text}` : "", width)),
    warningsRow: warnings.length > 0 ? body.length + filler : undefined,
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

  // Startup notices (config diagnostics) arrive before the sidebar mounts;
  // they are taken on the assumption that the tui will be fullscreen.
  const shown = () => (tui ? fullscreen : true) && visible && (tui?.terminal.columns ?? process.stdout.columns ?? 0) >= MIN_TERMINAL_WIDTH

  const panel = {
    render: (width: number) => {
      if (!store.snapshot || !theme || !tui) return []
      const out = renderPanel(store.snapshot, theme, width, tui.terminal.rows)
      warningsRow = out.warningsRow
      return out.lines
    },
    invalidate() {},
    handleMouse: (event: Mouse) => {
      if (event.type !== "press" || event.button !== "left" || event.y !== warningsRow || !ctx) return
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

  onTui((t, th) => {
    tui = t
    theme = th
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
      refresh(c)
    },
  })
}
