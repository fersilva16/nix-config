// Extension output and dialogs in the opencode-style modal. Multi-line
// ctx.ui.notify output (/goal, /todo, /mcp status, /loop status, /hooks, ...)
// opens a scrollable dialog instead of a sidebar notice or transcript lines;
// one-liners keep going to the sidebar. ctx.ui.select, confirm, input and
// editor (permission gate, MCP forms, /fallback, /goal, project trust) are
// drawn as dialogs too; omo still owns their keys, countdowns and answers.
import { CURSOR_MARKER, Key, matchesKey, wrapTextWithAnsi } from "@earendil-works/pi-tui"
import { cardInner, cardRow, promptStyle } from "./core/card.ts"
import { type ExtensionDialog, onDialog, onNotify, onTui } from "./core/host.ts"
import { MODAL_WIDTH, type ModalCtx, modalFrame, openModal } from "./core/modal.ts"
import { stripAnsi } from "./core/style.ts"
import type { Component, Theme, Tui } from "./core/types.ts"

type Pi = { on(event: "session_start", handler: (event: unknown, ctx: ModalCtx) => void): void }
type Frame = ReturnType<typeof modalFrame>

const TITLES: Record<string, [title: string, token: string]> = {
  error: ["Error", "error"],
  warning: ["Warning", "warning"],
  info: ["Notice", "text"],
}

// Rows the dialog chrome takes around a body (blank, header, blank ... blank,
// hints, blank), plus a margin so the dialog never fills the screen.
const CHROME_ROWS = 6
const height = (tui: Tui) => Math.max(3, Math.floor(tui.terminal.rows * 0.75) - CHROME_ROWS)

const wrap = (text: string, width: number) => text.split("\n").flatMap((l) => (l ? wrapTextWithAnsi(l, width) : [""]))

function showNotice(ctx: ModalCtx, message: string, type = "info"): Promise<void> {
  const [title, token] = TITLES[type] ?? TITLES.info
  return openModal<void>(ctx, (tui, theme, done) => {
    let top = 0
    let page = 1
    return {
      render(width) {
        const f = modalFrame(theme, width)
        const body = wrap(message, f.inner)
        page = height(tui)
        top = Math.max(0, Math.min(top, body.length - page))
        const scrolls = body.length > page
        const position = theme.fg("muted", `${top + 1}-${Math.min(top + page, body.length)} of ${body.length}`)
        return [
          f.line(),
          f.header(theme.fg(token, title)),
          f.line(),
          ...body.slice(top, top + page).map((l) => f.line(l)),
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

// omo's title, split into the header and message lines (confirm passes
// "title\nmessage"), with the countdown omo writes into its title text.
function heading(dialog: ExtensionDialog, theme: Theme, f: Frame, tui: Tui, reserved: number): string[] {
  const [head = "", ...message] = dialog.title.split("\n")
  const [first = "", ...more] = wrapTextWithAnsi(head, f.inner - 4)
  const countdown = dialog.kind === "editor" ? "" : stripAnsi(dialog.stock.titleText.text).slice(dialog.title.length).trim()
  const rows = [...more.map((l: string) => theme.bold(l)), ...(message.length > 0 ? wrap(message.join("\n"), f.inner) : [])]
  const room = Math.max(3, tui.terminal.rows - CHROME_ROWS - reserved - 2)
  const shown = rows.length > room ? [...rows.slice(0, room - 1), theme.fg("muted", `… ${rows.length - room + 1} more lines`)] : rows
  return [
    f.line(),
    f.header(countdown ? `${first} ${theme.fg("muted", countdown)}` : first),
    f.line(),
    ...(shown.length > 0 ? [...shown.map((l) => f.line(l)), f.line()] : []),
  ]
}

// An input or editor field as a small prompt card. omo's layout slicer counts
// the IME cursor marker as columns (see prompt.ts); the block cursor is drawn
// separately, so the marker goes.
function field(lines: string[], theme: Theme, f: Frame): string[] {
  return lines.map((l) => f.line(cardRow(promptStyle(theme), ` ${l.replaceAll(CURSOR_MARKER, "")}`, f.inner)))
}

const isBorder = (line: string) => stripAnsi(line).startsWith("─")

// omo's Editor draws [top border, content…, bottom border, autocomplete…];
// the borders go, keeping any "↑ n more" scroll note they carry.
function editorRows(editor: Component, width: number, theme: Theme): string[] {
  const lines = editor.render(width)
  let bottom = lines.length - 1
  while (bottom > 0 && !isBorder(lines[bottom])) bottom--
  const note = (line: string) => stripAnsi(line).replace(/─/g, "").trim()
  const [above, below] = [note(lines[0] ?? ""), note(lines[bottom] ?? "")]
  return [
    ...(above ? [theme.fg("dim", above)] : []),
    ...lines.slice(1, bottom),
    ...(below ? [theme.fg("dim", below)] : []),
    ...lines.slice(bottom + 1),
  ]
}

function renderDialog(dialog: ExtensionDialog, theme: Theme, tui: Tui, width: number): string[] {
  const f = modalFrame(theme, width)
  const fieldWidth = Math.max(1, cardInner(f.inner) - 1)
  if (dialog.kind === "select") {
    const { options, selectedIndex, maxVisibleOptions } = dialog.stock
    const start = Math.max(0, Math.min(selectedIndex - Math.floor(maxVisibleOptions / 2), options.length - maxVisibleOptions))
    const end = Math.min(start + maxVisibleOptions, options.length)
    const list = [
      ...(start > 0 ? [f.line(theme.fg("muted", `… ${start} more above`))] : []),
      ...options.slice(start, end).map((o, i) => (start + i === selectedIndex ? f.highlight("mdLink", o) : f.line(o))),
      ...(end < options.length ? [f.line(theme.fg("muted", `… ${options.length - end} more below`))] : []),
    ]
    return [
      ...heading(dialog, theme, f, tui, list.length),
      ...list,
      f.line(),
      f.line(f.hints([["select", "enter"], ["navigate", "↑↓"]])),
      f.line(),
    ]
  }
  if (dialog.kind === "input") {
    const rows = field(dialog.stock.input.render(fieldWidth), theme, f)
    return [...heading(dialog, theme, f, tui, rows.length), ...rows, f.line(), f.line(f.hints([["submit", "enter"]])), f.line()]
  }
  const rows = field(editorRows(dialog.stock.editor, fieldWidth, theme), theme, f)
  return [
    ...heading(dialog, theme, f, tui, rows.length),
    ...rows,
    f.line(),
    f.line(f.hints([["submit", "enter"], ["newline", "shift+enter"], ["external editor", "ctrl+g"]])),
    f.line(),
  ]
}

export default function dialogs(pi: Pi) {
  let ctx: ModalCtx | undefined
  let theme: Theme | undefined
  pi.on("session_start", (_e, c) => {
    ctx = c
  })
  // Only where a tui is mounted: headless and shared-host runs keep omo's.
  onTui((_t, th) => {
    theme = th
  })

  onNotify((message, type) => {
    if (!ctx || !theme || !message.trim().includes("\n")) return false
    void showNotice(ctx, message.trim(), type)
    return true
  })

  onDialog((dialog, tui) => {
    if (!theme) return undefined
    const th = theme
    const stock = dialog.stock as Component & { focused?: boolean }
    const component = {
      // omo's input and editor draw their cursor only while focused.
      get focused() {
        return stock.focused ?? false
      },
      set focused(value: boolean) {
        stock.focused = value
      },
      render: (width: number) => renderDialog(dialog, th, tui, width),
      invalidate: () => stock.invalidate(),
      handleInput: (data: string) => stock.handleInput?.(data),
    }
    return { component, width: MODAL_WIDTH }
  })
}
