// opencode-style model and thinking pickers. omo still builds its own pickers
// (ctrl+l and /model, /thinking, /scoped-models, /favorite-models) and keeps
// their logic: search ranking, catalog refresh, selection, ctrl+f favorites,
// ctrl+s save, reordering. Each one is drawn here as a centred dialog that
// reads the stock component's state and forwards keys to it. Thinking level
// changes (shift+tab, /thinking) show as a short toast instead of a status
// line.
import { keyText } from "@code-yeongyu/senpi"
import { Key, matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import { onSelector, onThinkingChange, onTui, type Selector } from "./core/host.ts"
import { type Hint, MODAL_WIDTH, modalFrame } from "./core/modal.ts"
import { fill, sgr, spread } from "./core/style.ts"
import type { Component, Theme, Tui } from "./core/types.ts"

type Model = { id: string; name?: string; provider: string }
type Frame = ReturnType<typeof modalFrame>
type Search = Component & { getValue(): string; prompt: string; placeholder: string }
type Stock = Component & { searchInput: Search; selectedIndex: number; updateList?(): void }
type Row = { header: string } | { gap: true } | { item: number; text: string; right: string }

// Rows around the list: pad, title, pad, search, pad, [list], pad, detail,
// up to two hint rows, pad.
const CHROME_ROWS = 10
const height = (tui: Tui) => Math.max(3, Math.floor(tui.terminal.rows * 0.75) - CHROME_ROWS)
const hint = (label: string, binding: string): Hint => [label, keyText(binding)]
const same = (a: Model | undefined, b: Model | undefined) => !!a && !!b && a.provider === b.provider && a.id === b.id

// One picker: a title, the stock search field, a list of rows and a detail
// line. `rows` lists every item in display order with the section headers,
// each row carrying its index in the stock component's own list; `select`
// sets that index, so ↑↓ move through what is shown and omo's enter/ctrl+f
// act on the item under the highlight.
type View<S extends Stock> = {
  title(stock: S, theme: Theme): string
  rows(stock: S, theme: Theme): Row[]
  selected(stock: S): number
  select?(stock: S, index: number): void
  detail(stock: S, theme: Theme): string
  hints(stock: S): Hint[]
}

function picker<S extends Stock>(view: View<S>, getTheme: () => Theme | undefined) {
  return ({ stock }: Selector, tui: Tui) => {
    const theme = getTheme()
    if (!theme) return undefined
    const s = stock as unknown as S
    s.searchInput.prompt = ""
    s.searchInput.placeholder = "Search"
    let scroll = 0
    const component = {
      get focused() {
        return stock.focused ?? false
      },
      set focused(value: boolean) {
        stock.focused = value
      },
      invalidate: () => stock.invalidate(),
      handleInput(data: string) {
        const step = matchesKey(data, Key.up) ? -1 : matchesKey(data, Key.down) ? 1 : 0
        if (step && view.select) {
          const items = view.rows(s, theme).flatMap((r) => ("item" in r ? [r.item] : []))
          const at = items.indexOf(view.selected(s))
          if (items.length > 0) view.select(s, items[(at + step + items.length) % items.length])
        } else stock.handleInput?.(data)
        tui.requestRender()
      },
      render(width: number) {
        const f = modalFrame(theme, width)
        const rows = view.rows(s, theme)
        const page = Math.max(3, Math.min(rows.length, height(tui)))
        const at = rows.findIndex((r) => "item" in r && r.item === view.selected(s))
        // Keep the selected row in view, with its section header when it
        // is the first of its section.
        const top = at > 0 && "header" in rows[at - 1] ? at - 1 : at
        if (top >= 0 && top < scroll) scroll = top
        if (at >= scroll + page) scroll = at - page + 1
        scroll = Math.max(0, Math.min(scroll, rows.length - page))
        const body = rows.slice(scroll, scroll + page).map((r) => row(r, r === rows[at], theme, f))
        if (rows.length === 0) body.push(f.line(theme.fg("muted", "No matching models")))
        return [
          f.line(),
          f.header(view.title(s, theme)),
          f.line(),
          f.line(s.searchInput.render(f.inner)[0] ?? ""),
          f.line(),
          ...body,
          ...Array.from({ length: Math.max(0, page - body.length) }, () => f.line()),
          f.line(),
          f.line(view.detail(s, theme)),
          ...hintRows(view.hints(s), f).map((h) => f.line(h)),
          f.line(),
        ]
      },
    }
    return { component, width: MODAL_WIDTH }
  }
}

// The checklists have more hints than one row holds; they wrap between hints.
function hintRows(hints: Hint[], f: Frame): string[] {
  const rows: Hint[][] = [[]]
  for (const h of hints) {
    const last = rows[rows.length - 1]
    if (last.length > 0 && visibleWidth(f.hints([...last, h])) > f.inner) rows.push([h])
    else last.push(h)
  }
  return rows.map((r) => f.hints(r))
}

function row(r: Row, selected: boolean, theme: Theme, f: Frame): string {
  if ("gap" in r) return f.line()
  if ("header" in r) return f.line(theme.fg("mdHeading", theme.bold(r.header)))
  if (selected) return f.highlight("mdLink", spread(r.text, r.right, f.inner))
  return f.line(spread(r.text, theme.fg("muted", r.right), f.inner))
}

// The current model (or level) carries opencode's ● in the gutter.
const mark = (current: boolean, theme: Theme) => (current ? theme.fg("accent", "● ") : "  ")
const label = (m: Model) => m.name || m.id

// ctrl+l, /model. With no search the list is grouped as in opencode:
// favorites first, then one section per provider in omo's order (the current
// model's provider first). A search shows omo's ranked matches flat, with
// each model's provider on the right.
type ModelItem = { fullId: string; provider: string; id: string; model: Model }
type ModelStock = Stock & {
  filteredModels: ModelItem[]
  scopedModelItems: ModelItem[]
  currentModel?: Model
  favoriteIds: string[] | null
  favoriteIdsAtOpen: string[] | null
  scope: "all" | "narrowed"
  errorMessage?: string
  refreshStatusMessage?: string
  refreshStatusSuccess?: boolean
}

const modelView: View<ModelStock> = {
  title(s, theme) {
    if (s.scopedModelItems.length === 0) return "Select model"
    const scope = (name: string) => theme.fg(s.scope === name ? "accent" : "muted", name)
    return `Select model  ${scope("all")}${theme.fg("dim", " · ")}${scope("narrowed")}`
  },
  rows(s, theme) {
    const favorite = (id: string) => s.favoriteIds !== null && s.favoriteIds.includes(id)
    const entry = (item: ModelItem, index: number, provider: boolean): Row => ({
      item: index,
      text: `${mark(same(s.currentModel, item.model), theme)}${label(item.model)}`,
      right: [provider ? item.provider : "", favorite(item.fullId) ? "★" : ""].filter(Boolean).join(" "),
    })
    const items = s.filteredModels.map((item, index) => ({ item, index }))
    if (s.searchInput.getValue()) return items.map(({ item, index }) => entry(item, index, true))
    const pinned = s.favoriteIdsAtOpen
    const sections = new Map<string, Row[]>()
    for (const { item, index } of items) {
      const section = pinned !== null && pinned.includes(item.fullId) ? "Favorites" : item.provider
      if (!sections.has(section)) sections.set(section, [])
      sections.get(section)?.push(entry(item, index, false))
    }
    const order = [...sections.keys()].sort((a, b) => Number(b === "Favorites") - Number(a === "Favorites"))
    return order.flatMap((section, i) => [...(i > 0 ? [{ gap: true } as const] : []), { header: section }, ...(sections.get(section) ?? [])])
  },
  selected: (s) => s.selectedIndex,
  select(s, index) {
    s.selectedIndex = index
    s.updateList?.()
  },
  detail(s, theme) {
    if (s.errorMessage) return theme.fg("error", s.errorMessage.split("\n")[0])
    if (s.refreshStatusMessage) return theme.fg(s.refreshStatusSuccess ? "success" : "muted", s.refreshStatusMessage)
    const item = s.filteredModels[s.selectedIndex]
    return item ? theme.fg("muted", `${item.provider}/${item.id}`) : ""
  },
  hints: (s) => [
    hint("favorite", "app.models.toggleFavorite"),
    ...(s.scopedModelItems.length > 0 ? [hint("catalog", "tui.input.tab")] : []),
  ],
}

// /thinking. omo's SelectList holds the (searched) levels; its labels start
// with "✓ " on the current one and descriptions end in "· default" on the
// saved default.
type Level = { value: string; label: string; description?: string }
type ThinkingStock = Stock & { selectList: { filteredItems: Level[]; selectedIndex: number } }

const thinkingView: View<ThinkingStock> = {
  title: () => "Thinking level",
  rows: (s, theme) =>
    s.selectList.filteredItems.map((level, index) => ({
      item: index,
      text: `${mark(level.label.startsWith("✓"), theme)}${level.value}`,
      right: level.description?.endsWith("· default") ? "default" : "",
    })),
  selected: (s) => s.selectList.selectedIndex,
  select(s, index) {
    s.selectList.selectedIndex = index
  },
  detail(s, theme) {
    const level = s.selectList.filteredItems[s.selectList.selectedIndex]
    return theme.fg("muted", level?.description?.replace(/ · default$/, "") ?? "")
  },
  hints: () => [hint("set default", "app.thinking.save"), hint("cycle", "app.thinking.cycle")],
}

// /scoped-models and /favorite-models: checklists whose order matters (it is
// the ctrl+p cycle order), so they stay in omo's order, not grouped.
type CheckItem = { fullId: string; model?: Model; enabled?: boolean; favorite?: boolean }
type CheckStock = Stock & {
  filteredItems: CheckItem[]
  isDirty: boolean
  allIds: string[]
  enabledIds?: string[] | null
  favoriteIds?: string[] | null
  currentModel?: Model
}

function checklist(
  title: string,
  checked: (item: CheckItem) => boolean,
  ids: (s: CheckStock) => string[] | null | undefined,
  noun: string,
  primary: () => Hint[],
): View<CheckStock> {
  return {
    title: (s, theme) => (s.isDirty ? `${title}  ${theme.fg("warning", "unsaved")}` : title),
    rows: (s, theme) =>
      s.filteredItems.map((item, index) => ({
        item: index,
        text: `${checked(item) ? theme.fg("success", "✓ ") : "  "}${item.model ? label(item.model) : theme.fg("muted", item.fullId)}${same(s.currentModel, item.model) ? theme.fg("accent", " ●") : ""}`,
        right: item.model?.provider ?? "unavailable",
      })),
    selected: (s) => s.selectedIndex,
    select(s, index) {
      s.selectedIndex = index
      s.updateList?.()
    },
    detail(s, theme) {
      const list = ids(s)
      const count = list === null || list === undefined ? `all ${noun}` : `${list.length}/${s.allIds.length} ${noun}`
      const item = s.filteredItems[s.selectedIndex]
      return theme.fg("muted", [count, item ? item.fullId : ""].filter(Boolean).join(" · "))
    },
    hints: () => [
      ...primary(),
      hint("save", "app.models.save"),
      hint("all", "app.models.enableAll"),
      hint("clear", "app.models.clearAll"),
      hint("provider", "app.models.toggleProvider"),
      ["reorder", `${keyText("app.models.reorderUp")}/${keyText("app.models.reorderDown")}`],
    ],
  }
}

const scopedView = checklist("Scoped models", (item) => !!item.model && !!item.enabled, (s) => s.enabledIds, "enabled", () => [hint("toggle", "tui.select.confirm")])
const favoriteView = checklist("Favorite models", (item) => !!item.favorite, (s) => s.favoriteIds, "favorites", () => [
  hint("select", "tui.select.confirm"),
  hint("favorite", "app.models.toggleFavorite"),
])

// A toast in the top-right corner for a thinking level change; each change
// replaces the last and restarts its timer. It never takes focus.
const TOAST_MS = 1800
type ToastTui = Tui & { showOverlay(component: Component, options: Record<string, unknown>): { hide(): void } }

function toaster(getTui: () => ToastTui | undefined, getTheme: () => Theme | undefined) {
  let shown: { hide(): void } | undefined
  let timer: ReturnType<typeof setTimeout> | undefined
  let last: { level: string; saved: boolean } | undefined
  return (level: string, saved: boolean): boolean => {
    const tui = getTui()
    const theme = getTheme()
    if (!tui || !theme) return false
    // Picking a level reports it twice (the change, then the pick); keep
    // "saved" from whichever said so.
    const keep = !!shown && last?.level === level && last.saved
    last = { level, saved: saved || keep }
    const text = `${theme.fg("muted", "Thinking")} ${theme.fg("warning", theme.bold(level))}${last.saved ? theme.fg("muted", " · default") : ""}`
    const panel = sgr(theme, "userMessageBg", "bg")
    const bar = theme.fg("warning", "┃")
    const toast: Component = {
      render: (width) => [bar + fill(panel, "", width - 1), bar + fill(panel, `  ${truncateToWidth(text, width - 3)}`, width - 1), bar + fill(panel, "", width - 1)],
      invalidate() {},
    }
    shown?.hide()
    clearTimeout(timer)
    shown = tui.showOverlay(toast, { anchor: "top-right", width: 32, margin: 1, nonCapturing: true })
    timer = setTimeout(() => {
      shown?.hide()
      shown = undefined
    }, TOAST_MS)
    return true
  }
}

export default function pickers() {
  let theme: Theme | undefined
  let tui: ToastTui | undefined
  // Only where a tui is mounted: headless and shared-host runs keep omo's.
  onTui((t, th) => {
    tui = t as ToastTui
    theme = th
  })
  const current = () => theme
  onSelector("ModelSelectorComponent", picker(modelView, current))
  onSelector("ThinkingSelectorComponent", picker(thinkingView, current))
  onSelector("ScopedModelsSelectorComponent", picker(scopedView, current))
  onSelector("FavoriteModelsSelectorComponent", picker(favoriteView, current))
  onThinkingChange(toaster(() => tui, current))
}
