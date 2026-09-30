// omo's session navigation pickers as opencode-style dialogs: /tree, /fork and
// /resume (and their keys; omo's /sessions and ctrl+x l are /resume too).
// omo still builds each picker and owns its keys, filters, folding, labels and
// navigation; these only draw it in the dialog chrome from core/modal.ts.
// /rename's input goes to the dialog hook in dialogs.ts, and the branch
// summary choice after /tree is an extension select that dialogs.ts draws.
import { onSelector, onTui, renameAsDialog } from "./core/host.ts"
import { MODAL_WIDTH, modalFrame } from "./core/modal.ts"
import { stripAnsi } from "./core/style.ts"
import type { Component, Theme, Tui } from "./core/types.ts"

type Frame = ReturnType<typeof modalFrame>
type Focusable = Component & { focused?: boolean }

// The tree's rows are wide (indent, labels, tool calls).
const TREE_WIDTH = 120
// Rows the dialog chrome takes around a list, plus a margin.
const CHROME_ROWS = 8

// omo's stock rows start with a two-column gutter: "› " on the selected row,
// two spaces elsewhere. The gutter goes; the selected row becomes the bar.
const GUTTER = /^((?:\x1b\[[0-9;]*m)*)(?:› | {2})/
function stockRows(lines: string[], f: Frame): string[] {
  return lines.map((l) => {
    const plain = stripAnsi(l)
    return plain.startsWith("› ") ? f.highlight("mdLink", plain.slice(2).trimEnd()) : f.line(l.replace(GUTTER, "$1"))
  })
}

// A dialog around omo's picker: keys go to omo's focus component.
function dialog(focus: Focusable, tui: Tui, theme: Theme, draw: (f: Frame) => string[]): Component & { focused: boolean } {
  return {
    get focused() {
      return focus.focused ?? false
    },
    set focused(value: boolean) {
      focus.focused = value
    },
    render: (width) => draw(modalFrame(theme, width)),
    invalidate: () => focus.invalidate(),
    handleInput(data) {
      focus.handleInput?.(data)
      tui.requestRender()
    },
  }
}

type TreeSelector = Component & {
  children: Component[]
  labelInput: Component | null
  treeList: Component & { getSearchQuery(): string }
}

function tree(sel: TreeSelector, theme: Theme, f: Frame): string[] {
  const body = sel.treeList.render(f.inner + 2)
  // omo's last row is the position and filter, e.g. "(3/40) [no-tools]".
  const status = stripAnsi(body.pop() ?? "").trim()
  const query = sel.treeList.getSearchQuery()
  const help = sel.children.find((c) => c.constructor.name === "TreeHelp")
  return [
    f.line(),
    f.header("Session tree"),
    f.line(),
    f.line(query || theme.fg("muted", "Type to search")),
    f.line(),
    ...(sel.labelInput ? sel.labelInput.render(f.inner).map((l) => f.line(l.replace(GUTTER, "$1"))) : stockRows(body, f)),
    f.line(),
    f.line(theme.fg("muted", status)),
    ...(help?.render(f.inner).map((l) => f.line(l.replace(GUTTER, "$1"))) ?? []),
    f.line(),
  ]
}

type MessageList = Component & { messages: { id: string; text: string }[]; selectedIndex: number }

function fork(list: MessageList, theme: Theme, f: Frame, tui: Tui): string[] {
  const { messages, selectedIndex } = list
  const height = Math.max(3, Math.min(messages.length, Math.floor(tui.terminal.rows * 0.75) - CHROME_ROWS))
  const start = Math.max(0, Math.min(selectedIndex - Math.floor(height / 2), messages.length - height))
  const body = messages.slice(start, start + height).map((m, i) => {
    const text = m.text.replace(/\s+/g, " ").trim()
    return start + i === selectedIndex ? f.highlight("mdLink", text) : f.line(text)
  })
  return [
    f.line(),
    f.header("Fork from message"),
    f.line(),
    f.line(theme.fg("muted", "Copies the conversation up to this message into a new session")),
    f.line(),
    ...body,
    ...Array.from({ length: height - body.length }, () => f.line()),
    f.line(),
    f.line(`${f.hints([["fork", "enter"], ["navigate", "↑↓"]])}   ${theme.fg("muted", `${selectedIndex + 1} of ${messages.length}`)}`),
    f.line(),
  ]
}

type SessionSelector = Component & {
  mode: "list" | "rename"
  scope: "current" | "all"
  sortMode: string
  nameFilter: "all" | "named"
  renameInput: Component
  header: Component & { loading: boolean }
  sessionList: Component & { maxVisible: number; searchInput: Component }
}

const capital = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

function resume(sel: SessionSelector, theme: Theme, f: Frame): string[] {
  if (sel.mode === "rename") {
    return [
      f.line(),
      f.header("Rename session"),
      f.line(),
      f.line(sel.renameInput.render(f.inner)[0] ?? ""),
      f.line(),
      f.line(f.hints([["save", "enter"], ["cancel", "esc"]])),
      f.line(),
    ]
  }
  const list = sel.sessionList
  // omo's list: the search input, a blank row, then the sessions.
  const [, , ...body] = list.render(f.inner + 2)
  const scope = sel.header.loading ? "Loading…" : sel.scope === "current" ? "Current folder" : "All folders"
  const filters = `${scope} · Sort: ${capital(sel.sortMode)} · Name: ${sel.nameFilter === "named" ? "Named" : "All"}`
  // omo's header rows 2-3: key hints, or a status / delete confirmation.
  const [, ...hints] = sel.header.render(f.inner)
  return [
    f.line(),
    f.header("Resume session"),
    f.line(theme.fg("muted", filters)),
    f.line(),
    f.line(list.searchInput.render(f.inner)[0] ?? ""),
    f.line(),
    ...stockRows(body, f),
    ...Array.from({ length: Math.max(0, list.maxVisible + 1 - body.length) }, () => f.line()),
    f.line(),
    ...hints.filter((h) => h).map((h) => f.line(h)),
    f.line(),
  ]
}

export default function pickers() {
  let theme: Theme | undefined
  // Only where a tui is mounted: headless and shared-host runs keep omo's.
  onTui((_t, th) => {
    theme = th
  })

  onSelector("TreeSelectorComponent", ({ stock }, tui) => {
    const th = theme
    if (!th) return undefined
    const sel = stock as TreeSelector
    return { component: dialog(sel, tui, th, (f) => tree(sel, th, f)), width: TREE_WIDTH }
  })
  // omo focuses the fork picker's message list, which takes its keys.
  onSelector("UserMessageSelectorComponent", ({ stock }, tui) => {
    const th = theme
    if (!th) return undefined
    const list = (stock as Component & { getMessageList(): MessageList }).getMessageList()
    return { component: dialog(list, tui, th, (f) => fork(list, th, f, tui)), width: MODAL_WIDTH }
  })
  onSelector("SessionSelectorComponent", ({ stock }, tui) => {
    const th = theme
    if (!th) return undefined
    const sel = stock as SessionSelector
    return { component: dialog(sel, tui, th, (f) => resume(sel, th, f)), width: MODAL_WIDTH }
  })

  renameAsDialog()
}