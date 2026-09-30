// /settings, /trust, /login, /logout and /llama as opencode-style dialogs.
// omo builds these screens in the editor's place; core/host.ts hands each one
// here and it is drawn as a centred modal instead, with omo still owning its
// keys and state. /settings, the one opened most, is redrawn from its list's
// state (search, label/value rows, description, submenus). The rarer screens
// keep omo's content in the modal frame: its borders go, its title becomes
// the header and its "→" row the selection bar.
import { truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui"
import { onTakeover, onTui } from "./core/host.ts"
import { type Hint, MODAL_WIDTH, modalFrame } from "./core/modal.ts"
import { spread, stripAnsi } from "./core/style.ts"
import type { Component, Theme, Tui } from "./core/types.ts"

const FRAMED = new Set(["TrustSelectorComponent", "OAuthSelectorComponent", "LoginDialogComponent", "ExtensionSelectorComponent", "LlamaView"])
const SMALL_WIDTH = 72

// Settings. SettingsList, SelectSubmenu and the theme/warning submenus are
// omo internals read structurally.
type Input = Component & { prompt: string; placeholder: string; placeholderStyle(text: string): string; getValue(): string }
type SettingsItem = { label: string; currentValue: string; description?: string }
type SettingsList = {
  searchEnabled: boolean
  searchInput?: Input
  selectedIndex: number
  submenuComponent: Node | null
  submenuItemIndex: number | null
  items: SettingsItem[]
  getDisplayItems(): SettingsItem[]
}
type SelectItem = { value: string; label?: string; description?: string }
type Node = Component & {
  children?: Node[]
  text?: string
  settingsList?: SettingsList
  selectList?: { filteredItems: SelectItem[]; items: SelectItem[]; selectedIndex: number }
  inputComponent?: Node
}

type Row = { label: string; value: string }
type View = {
  title: string
  intro: string[]
  search?: Input
  rows: Row[]
  total: number
  selected: number
  description?: string
  empty: string
  hints: Hint[]
}

const isSettingsList = (n: unknown): n is SettingsList => typeof (n as SettingsList)?.getDisplayItems === "function"
const texts = (n: Node) => (n.children ?? []).filter((c) => typeof c.text === "string").map((c) => c.text as string)

// The screen currently showing: the innermost open submenu, titled by the
// setting it belongs to unless it names itself.
function view(node: Node | SettingsList, title: string, theme: Theme): View | undefined {
  if (isSettingsList(node)) {
    const items = node.getDisplayItems()
    if (node.submenuComponent) return view(node.submenuComponent, items[node.submenuItemIndex ?? -1]?.label ?? title, theme)
    const search = node.searchEnabled ? node.searchInput : undefined
    if (search) {
      search.prompt = ""
      search.placeholder = "Search"
      search.placeholderStyle = (text) => theme.fg("muted", text)
    }
    return {
      title,
      intro: [],
      search,
      rows: items.map((i) => ({ label: i.label, value: i.currentValue })),
      total: node.items.length,
      selected: node.selectedIndex,
      description: items[node.selectedIndex]?.description,
      empty: "No matching settings",
      hints: [
        ["change", "enter"],
        ["navigate", "↑↓"],
      ],
    }
  }
  if (node.settingsList) return view(node.settingsList, title, theme)
  if (node.inputComponent && node.children?.[0]) return view(node.children[0], title, theme)
  const [head, ...intro] = texts(node)
    .map(stripAnsi)
    // SelectSubmenu's own key hint; the dialog draws its own.
    .filter((t) => !t.includes("Esc to"))
  if (node.selectList) {
    const list = node.selectList
    return {
      title: head ?? title,
      intro,
      rows: list.filteredItems.map((i) => ({ label: i.label ?? i.value, value: i.description ?? "" })),
      total: list.items.length,
      selected: list.selectedIndex,
      empty: "No matching options",
      hints: [
        ["select", "enter"],
        ["navigate", "↑↓"],
      ],
    }
  }
  // The automatic-theme menu: intro text above a settings list.
  const list = node.children?.find(isSettingsList) as SettingsList | undefined
  const inner = list && view(list, title, theme)
  if (!inner || list.submenuComponent) return inner
  return { ...inner, title: head ?? title, intro }
}

const CHROME_ROWS = 10 // pads, header, gaps, search, description, hints
const wrap = (text: string, width: number) => text.split("\n").flatMap((l) => (l ? wrapTextWithAnsi(l, width) : [""]))

function renderSettings(stock: Node, theme: Theme, tui: Tui, width: number): string[] {
  const v = view(stock, "Settings", theme)
  if (!v) return renderFramed(stock, theme, width)
  const f = modalFrame(theme, width)
  const intro = v.intro.flatMap((t) => wrap(t, f.inner)).map((l) => f.line(theme.fg("muted", l)))
  const description = v.description ? wrap(v.description, f.inner) : []
  const room = Math.max(3, Math.floor(tui.terminal.rows * 0.75) - CHROME_ROWS - intro.length - description.length)
  const height = Math.min(room, Math.max(1, v.total))
  const start = Math.max(0, Math.min(v.selected - Math.floor(height / 2), v.rows.length - height))
  const shown = v.rows.slice(start, start + height)
  const labelWidth = Math.min(36, Math.max(0, ...v.rows.map((r) => r.label.length)))
  const row = (r: Row, i: number) => {
    const label = r.label.padEnd(labelWidth)
    if (start + i === v.selected) return f.highlight("mdLink", spread(label, r.value, f.inner))
    return f.line(spread(label, theme.fg("muted", r.value), f.inner))
  }
  const body = shown.length > 0 ? shown.map(row) : [f.line(theme.fg("muted", v.empty))]
  const position = v.rows.length > height ? `   ${theme.fg("muted", `${v.selected + 1} of ${v.rows.length}`)}` : ""
  return [
    f.line(),
    f.header(v.title),
    f.line(),
    ...(intro.length > 0 ? [...intro, f.line()] : []),
    ...(v.search ? [f.line(v.search.render(f.inner)[0] ?? ""), f.line()] : []),
    ...body,
    ...Array.from({ length: Math.max(0, height - body.length) }, () => f.line()),
    ...(description.length > 0 ? [f.line(), ...description.map((l) => f.line(theme.fg("muted", l)))] : []),
    f.line(),
    f.line(`${f.hints(v.hints)}${position}`),
    f.line(),
  ]
}

// omo's own lines in the modal frame. The "→ " row becomes the selection bar
// (the arrow turns into spaces, keeping the row's text where it was). Text
// rows carry one column of padding, dropped (after any leading colour codes)
// so they line up with the header; list rows without padding lose a column
// of their gutter instead.
const PAD = /^((?:\x1b\[[0-9;]*m)*) /
const isBorder = (text: string) => /^─+$/.test(text.trim())
const isBlank = (l: string) => !stripAnsi(l).trim()

function selection(line: string): string | undefined {
  const text = stripAnsi(line)
  const arrow = text.search(/\S/)
  return text.startsWith("→ ", arrow) ? `${text.slice(0, arrow)}  ${text.slice(arrow + 2)}`.replace(PAD, "$1") : undefined
}

function renderFramed(stock: Component, theme: Theme, width: number): string[] {
  const f = modalFrame(theme, width)
  const lines = stock.render(f.inner + 1).filter((l) => !isBorder(stripAnsi(l)))
  const at = lines.findIndex((l) => !isBlank(l))
  const title = at >= 0 ? stripAnsi(lines[at]).trim() : ""
  const body = lines.slice(at + 1).filter((l, i, all) => !isBlank(l) || (i > 0 && !isBlank(all[i - 1])))
  while (body.length > 0 && isBlank(body[0])) body.shift()
  while (body.length > 0 && isBlank(body[body.length - 1])) body.pop()
  const row = (l: string) => {
    const selected = selection(l)
    // Inputs fill the width they were given, one column past the frame.
    return selected === undefined ? f.line(truncateToWidth(l.replace(PAD, "$1"), f.inner, "")) : f.highlight("mdLink", selected)
  }
  return [f.line(), f.header(title), f.line(), ...body.map(row), ...(body.length > 0 ? [f.line()] : [])]
}

export default function settings() {
  let theme: Theme | undefined
  // Only where a tui is mounted: headless and shared-host runs keep omo's.
  onTui((_t, th) => {
    theme = th
  })

  onTakeover((takeover, tui) => {
    const { name, stock } = takeover
    const th = theme
    const settings = name === "SettingsSelectorComponent"
    if (!th || (!settings && !FRAMED.has(name))) return undefined
    const target = () => takeover.target ?? stock
    const component = {
      // Inputs (login prompts) draw their cursor only while focused.
      get focused() {
        return target().focused ?? false
      },
      set focused(value: boolean) {
        target().focused = value
      },
      render: (width: number) => (settings ? renderSettings(stock as Node, th, tui, width) : renderFramed(stock, th, width)),
      invalidate: () => stock.invalidate(),
      handleInput: (data: string) => target().handleInput?.(data),
    }
    return { component, width: settings || name === "OAuthSelectorComponent" || name === "LlamaView" ? MODAL_WIDTH : SMALL_WIDTH }
  })
}
