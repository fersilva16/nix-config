// opencode-style right sidebar. omo's fullscreen renderer lays out a flex
// tree; wrapping its root in an HStack (core/host.ts wrapLayout) gives the
// sidebar a real column, so transcript, editor and footer reflow beside it
// instead of being painted over. Its content comes from core/store.ts.
import { HStack, VStack, visibleWidth } from "@earendil-works/pi-tui"
import { afterSelection, isModalFrame, onTui, wrapLayout } from "./core/host.ts"
import { refresh, type Snapshot, store } from "./core/store.ts"
import { ESCAPE_AT_START, homePath, paint } from "./core/style.ts"
import type { Component, Ctx, Theme, Tui } from "./core/types.ts"

const WIDTH = 40
const MIN_TERMINAL_WIDTH = 100
const MARGIN_LEFT = 2
const MARGIN_X = 2
const MARGIN_Y = 1
const BG = "userMessageBg"
const VERSION = process.execPath.match(/binary-runtime\/([^/]+)\//)?.[1] ?? ""

type Pi = {
  registerCommand(name: string, options: { description: string; handler: (args: string, ctx: Ctx) => Promise<void> }): void
}

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

function renderPanel(state: Snapshot, theme: Theme, width: number, rows: number): string[] {
  const body: string[] = []
  const line = (text = "") => body.push(text)
  const muted = (text: string) => line(theme.fg("muted", text))

  line()
  line(theme.bold(state.title))
  muted(state.sessionId)
  line()
  line(theme.bold("Context"))
  muted(`${state.tokens === undefined ? "?" : state.tokens.toLocaleString("en-US")} tokens`)
  muted(`${state.percent === undefined ? "?" : `${Math.round(state.percent)}%`} used`)
  muted(`$${state.cost.toFixed(2)} spent`)
  if (state.files.length > 0) {
    line()
    line(theme.bold("Modified Files"))
    for (const f of state.files) muted(f)
  }

  const location = `${homePath(state.cwd)}${state.branch ? `:${state.branch}` : ""}`
  const footer = [location, "", `${theme.fg("success", "•")} ${theme.bold("OmO")} ${theme.fg("muted", VERSION)}`, ""]
  const filler = Math.max(1, rows - body.length - footer.length)
  return [...body, ...Array(filler).fill(""), ...footer].map((text) => paint(theme, BG, text ? `  ${text}` : "", width))
}

export default function sidebar(pi: Pi) {
  let visible = true
  let theme: Theme | undefined
  let tui: Tui | undefined

  const panel: Component = {
    render: (width) => (store.snapshot && theme && tui ? renderPanel(store.snapshot, theme, width, tui.terminal.rows) : []),
    invalidate() {},
  }
  // omo's layout pastes columns side by side without resetting SGR state, so
  // a transcript row that ends mid-background (tool blocks) would bleed into
  // whatever follows. Margins reset every row.
  const blank: Component = {
    render: (width) => Array.from({ length: tui?.terminal.rows ?? 0 }, () => `\x1b[0m${" ".repeat(width)}`),
    invalidate() {},
  }

  onTui((t, th) => {
    tui = t
    theme = th
    const fullscreen = wrapLayout(t, (inner) => {
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

  pi.registerCommand("sidebar", {
    description: "Toggle the right sidebar",
    handler: async (_args, ctx) => {
      visible = !visible
      refresh(ctx)
    },
  })
}
