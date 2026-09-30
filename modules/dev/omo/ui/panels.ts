// omo's own panels in the opencode-style modal. /help, /history, /diff and
// /files are stock overlays: they are redrawn on the modal panel, their
// accent borders dropped, the selected list row as a highlight bar, while omo
// keeps their keys and results. /hotkeys, /session and /changelog, which omo
// appends to the transcript, open as a scrollable modal instead. The
// fullscreen transcript search and the "?" shortcut hint get the panel fill
// in place (the search keeps omo's layout, which its mouse hit-test reads).
// /tui only sends a one-line notice, which already goes to the sidebar.
import { CURSOR_MARKER, Key, matchesKey } from "@earendil-works/pi-tui"
import { onOverlay, onShortcutOverlay, onTranscriptPanel, onTui, type StockOverlay, type TranscriptPanel } from "./core/host.ts"
import { MODAL_WIDTH, type ModalCtx, modalFrame, openModal } from "./core/modal.ts"
import { fill, sgr, stripAnsi } from "./core/style.ts"
import type { Component, Theme, Tui } from "./core/types.ts"

type Pi = { on(event: "session_start", handler: (event: unknown, ctx: ModalCtx) => void): void }
type Frame = ReturnType<typeof modalFrame>

// Blank, header, blank above the body; blank below it (hints bring their own).
const CHROME_ROWS = 6
const PANEL = "userMessageBg"

const isBorder = (line: string) => /^─+$/.test(stripAnsi(line).trim())
const isBlank = (line: string) => stripAnsi(line).trim() === ""
const isHints = (line: string) => stripAnsi(line).includes(" • ")

function trimBlank(lines: string[]): string[] {
  let start = 0
  let end = lines.length
  while (start < end && isBlank(lines[start])) start++
  while (end > start && isBlank(lines[end - 1])) end--
  return lines.slice(start, end)
}

// omo's SelectList marks the selected row "→ " and indents the rest by two
// columns; the modal draws the selected row as a bar at the same inset.
function listRow(f: Frame, line: string): string {
  const text = stripAnsi(line)
  if (text.startsWith("→ ")) return f.highlight("mdLink", text.slice(2))
  return f.line(text.startsWith("  ") ? line.replace(/^((?:\x1b\[[0-9;]*m)*) {2}/, "$1") : line)
}

// A bordered stock panel: [border, title, body…, hints, border].
function panelRows(stock: Component, theme: Theme, width: number, title?: string, scrollHint = false): string[] {
  const f = modalFrame(theme, width)
  const lines = stock.render(f.inner).map((l) => l.replaceAll(CURSOR_MARKER, "")).filter((l) => !isBorder(l))
  const head = title ?? stripAnsi(lines.shift() ?? "").trim()
  const stockHints = lines.length > 1 && isHints(lines.at(-1)!) ? stripAnsi(lines.pop()!).trim() : undefined
  const hints = stockHints ? theme.fg("muted", stockHints.replaceAll(" • ", "   ")) : scrollHint && f.hints([["scroll", "↑↓"]])
  return [
    f.line(),
    f.header(head),
    f.line(),
    ...trimBlank(lines).map((l) => listRow(f, l)),
    f.line(),
    ...(hints ? [f.line(hints), f.line()] : []),
  ]
}

function framed(stock: Component, theme: Theme, title?: string, scrollHint = false): Component {
  const s = stock as Component & { focused?: boolean; dispose?(): void }
  return {
    get focused() {
      return s.focused ?? false
    },
    set focused(value: boolean) {
      s.focused = value
    },
    render: (width) => panelRows(stock, theme, width, title, scrollHint),
    invalidate: () => stock.invalidate(),
    handleInput: (data) => stock.handleInput?.(data),
  } as Component
}

// The search bar keeps omo's three rows and columns; its box turns into the
// panel fill, so the ↑/↓ buttons stay where the mouse hit-test expects them.
function flatSearch(stock: Component, theme: Theme): Component {
  const s = stock as Component & { focused?: boolean }
  const panel = sgr(theme, PANEL, "bg")
  return {
    get focused() {
      return s.focused ?? false
    },
    set focused(value: boolean) {
      s.focused = value
    },
    render: (width) =>
      stock.render(width).map((line) => fill(panel, line.replaceAll(CURSOR_MARKER, "").replace(/[┌┐└┘│─]/g, " "), width)),
    invalidate: () => stock.invalidate(),
    handleInput: (data) => stock.handleInput?.(data),
  } as Component
}

const centred = (tui: Tui) => ({ width: Math.min(MODAL_WIDTH, tui.terminal.columns - 4), anchor: "center", maxHeight: "100%" })

function restyle(overlay: StockOverlay, theme: Theme, tui: Tui) {
  const { kind, component } = overlay
  if (kind === "search") return { component: flatSearch(component, theme) }
  if (kind === "help") return { component: framed(component, theme, "Help", true), options: centred(tui), reserveRows: CHROME_ROWS }
  // Only bordered panels (history, /diff, /files); anything else another
  // extension shows is left as it is.
  if (!isBorder(component.render(MODAL_WIDTH)[0] ?? "")) return undefined
  return { component: framed(component, theme), options: centred(tui) }
}

const TITLES: Record<TranscriptPanel, string> = {
  hotkeys: "Keyboard Shortcuts",
  session: "Session Info",
  changelog: "What's New",
}

// The panel's text, scrollable, under the title omo gave it.
function showPanel(ctx: ModalCtx, title: string, body: (width: number) => string[]): Promise<void> {
  return openModal<void>(ctx, (tui, theme, done) => {
    let top = 0
    let page = 1
    // /changelog runs to thousands of lines; they are laid out once per width.
    let laid: { width: number; rows: string[] } | undefined
    const layout = (width: number) => {
      const lines = trimBlank(body(width).filter((l) => !isBorder(l)))
      if (stripAnsi(lines[0] ?? "").trim() === title) lines.splice(0, 1)
      return trimBlank(lines)
    }
    return {
      render(width) {
        const f = modalFrame(theme, width)
        if (laid?.width !== f.inner) laid = { width: f.inner, rows: layout(f.inner) }
        const { rows } = laid
        page = Math.max(3, tui.terminal.rows - 2 - CHROME_ROWS - 2)
        top = Math.max(0, Math.min(top, rows.length - page))
        const scrolls = rows.length > page
        const position = theme.fg("muted", `${top + 1}-${Math.min(top + page, rows.length)} of ${rows.length}`)
        return [
          f.line(),
          f.header(title),
          f.line(),
          ...rows.slice(top, top + page).map((l) => f.line(l)),
          f.line(),
          ...(scrolls ? [f.line(`${f.hints([["scroll", "↑↓"]])}   ${position}`), f.line()] : []),
        ]
      },
      invalidate() {},
      handleInput(data) {
        if (matchesKey(data, Key.escape) || matchesKey(data, Key.enter) || data === "q") return done()
        const step = matchesKey(data, Key.up) || data === "k" ? -1 : matchesKey(data, Key.down) || data === "j" ? 1 : 0
        const jump = matchesKey(data, Key.pageUp) ? -page : matchesKey(data, Key.pageDown) || data === " " ? page : 0
        if (step || jump) {
          top = Math.max(0, top + step + jump)
          tui.requestRender()
        }
      },
    }
  })
}

// Rows under the hint: the prompt card and footer, so it sits just above them.
const PROMPT_ROWS = 7

// [border, title, grid…, hint, border] as a panel card above the prompt.
function shortcutCard(theme: Theme, render: (width: number) => string[]): Component {
  return {
    render(width) {
      const f = modalFrame(theme, width)
      const lines = render(f.inner).filter((l) => !isBorder(l))
      const title = stripAnsi(lines.shift() ?? "").trim()
      const hint = stripAnsi(lines.pop() ?? "").trim()
      return [f.line(), f.line(theme.bold(title)), f.line(), ...lines.map((l) => f.line(l)), f.line(), f.line(theme.fg("muted", hint)), f.line()]
    },
    invalidate() {},
  }
}

export default function panels(pi: Pi) {
  let ctx: ModalCtx | undefined
  let theme: Theme | undefined
  pi.on("session_start", (_e, c) => {
    ctx = c
  })
  // Only where a tui is mounted: headless and shared-host runs keep omo's.
  onTui((_t, th) => {
    theme = th
  })

  onOverlay((overlay, tui) => (theme ? restyle(overlay, theme, tui) : undefined))

  onTranscriptPanel((panel, render) => {
    if (!ctx || !theme) return false
    void showPanel(ctx, TITLES[panel], render)
    return true
  })

  onShortcutOverlay((render) =>
    theme ? { component: shortcutCard(theme, render), options: { width: 72, anchor: "bottom-left", margin: { left: 2, bottom: PROMPT_ROWS } } } : undefined,
  )
}
