// opencode-style session picker: /sessions opens a centred dialog listing this
// folder's sessions grouped by day, newest first, with fuzzy search. omo's own
// /resume stays available for its extras (all folders, rename, delete).
import { SessionManager } from "@earendil-works/pi-coding-agent"
import { fuzzyFilter, Input, Key, matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import { paint, spread, type Theme } from "./stats.ts"

const BG = "userMessageBg"
const PAD = 2
const CHROME = 4 // title, search, blank row above the list, blank row below it

type Session = { path: string; name?: string; firstMessage: string; modified: Date }
type Composite = (screen: string[], width: number, height: number) => string[]
type Tui = { requestRender(): void; terminal: { rows: number }; compositeOverlays?: Composite }

// Terminals have no translucency, so the backdrop repaints the screen under
// the dialog flat: every cell keeps its text but loses its colours to one
// faded fg/bg pair. It hooks the fullscreen renderer's compositeOverlays (omo
// internals), which receives the finished frame just before overlays land.
// While set, sidebar.ts skips its per-row colour reset, which would otherwise
// cut the fade off at the transcript edge.
export const BACKDROP = Symbol.for("omo-ui.backdrop")
const ESCAPES = /\x1b\[[0-9;:?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b_[^\x1b]*\x1b\\/g

function installBackdrop(tui: Tui, theme: Theme): () => void {
  const original = tui.compositeOverlays
  if (!original) return () => {}
  const bg = theme.fg("borderMuted", "\u0000").split("\u0000")[0].replace("[38;", "[48;")
  const fg = theme.fg("border", "\u0000").split("\u0000")[0]
  const state = globalThis as { [BACKDROP]?: boolean }
  state[BACKDROP] = true
  tui.compositeOverlays = function (this: Tui, screen, width, height) {
    const faded = screen.map((line) => {
      const text = line.replace(ESCAPES, "")
      return `${bg}${fg}${text}${" ".repeat(Math.max(0, width - visibleWidth(text)))}\x1b[0m`
    })
    return original.call(this, faded, width, height)
  }
  return () => {
    tui.compositeOverlays = original
    state[BACKDROP] = false
    tui.requestRender()
  }
}
type Ctx = {
  cwd: string
  sessionManager: { getSessionFile(): string | undefined }
  switchSession(path: string): Promise<{ cancelled?: boolean }>
  ui: {
    custom<T>(
      factory: (tui: Tui, theme: Theme, keybindings: unknown, done: (value: T) => void) => unknown,
      options: { overlay: true; overlayOptions: Record<string, unknown> },
    ): Promise<T>
    notify(message: string, level: "info" | "warning" | "error"): void
  }
}
type Pi = {
  registerCommand(name: string, options: { description: string; handler: (args: string, ctx: Ctx) => Promise<void> }): void
}
type Row = { header: string } | { session: Session; index: number }

const title = (s: Session) => (s.name ?? s.firstMessage).split("\n")[0].trim()

function dayLabel(date: Date, now: Date): string {
  const day = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const diff = Math.round((day(now) - day(date)) / 86_400_000)
  if (diff === 0) return "Today"
  if (diff === 1) return "Yesterday"
  return date.toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: date.getFullYear() === now.getFullYear() ? undefined : "numeric",
  })
}

class Picker {
  private readonly input = new Input({ prompt: "", placeholder: "Search" })
  private matches: Session[]
  private selected = 0
  private scroll = 0
  private _focused = false

  constructor(
    private readonly sessions: Session[],
    private readonly current: string | undefined,
    private readonly tui: Tui,
    private readonly theme: Theme,
    private readonly done: (path: string | undefined) => void,
  ) {
    this.matches = sessions
  }

  get focused() {
    return this._focused
  }
  set focused(value: boolean) {
    this._focused = value
    this.input.focused = value
  }

  handleInput(data: string) {
    if (matchesKey(data, Key.escape)) return this.done(undefined)
    if (matchesKey(data, Key.enter)) return this.done(this.matches[this.selected]?.path)
    if (matchesKey(data, Key.up) || matchesKey(data, Key.ctrl("p"))) this.move(-1)
    else if (matchesKey(data, Key.down) || matchesKey(data, Key.ctrl("n"))) this.move(1)
    else {
      this.input.handleInput(data)
      const hits = new Set(fuzzyFilter(this.sessions, this.input.getValue(), title))
      this.matches = this.sessions.filter((s) => hits.has(s))
      this.selected = 0
      this.scroll = 0
    }
    this.tui.requestRender()
  }

  private move(delta: number) {
    if (this.matches.length > 0) this.selected = (this.selected + delta + this.matches.length) % this.matches.length
  }

  private rows(): Row[] {
    const now = new Date()
    const rows: Row[] = []
    let last = ""
    this.matches.forEach((session, index) => {
      const label = dayLabel(session.modified, now)
      if (label !== last) rows.push({ header: label })
      last = label
      rows.push({ session, index })
    })
    return rows
  }

  render(width: number): string[] {
    const th = this.theme
    const inner = width - 2 * PAD
    const pad = (text: string, token = BG) => paint(th, token, `${" ".repeat(PAD)}${truncateToWidth(text, inner)}`, width)
    const height = Math.max(3, Math.floor(this.tui.terminal.rows * 0.7) - CHROME)

    const rows = this.rows()
    const at = rows.findIndex((r) => "session" in r && r.index === this.selected)
    // Keep the selected row visible, and its day header when it is the first of its group.
    const top = at > 0 && "header" in rows[at - 1] ? at - 1 : at
    if (top < this.scroll) this.scroll = Math.max(0, top)
    if (at >= this.scroll + height) this.scroll = at - height + 1

    const body = rows.slice(this.scroll, this.scroll + height).map((row) => {
      if ("header" in row) return pad(th.fg("accent", th.bold(row.header)))
      const { session, index } = row
      const time = session.modified.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })
      const marker = session.path === this.current ? "● " : "  "
      const name = truncateToWidth(`${marker}${title(session)}`, inner - visibleWidth(time) - 2)
      if (index === this.selected) return pad(spread(th.fg("accent", th.bold(name)), th.fg("accent", time), inner), "selectedBg")
      return pad(spread(name, th.fg("muted", time), inner))
    })
    if (rows.length === 0) body.push(pad(th.fg("muted", "No matching sessions")))

    const search = this.input.render(inner)[0] ?? ""
    return [
      pad(spread(th.bold("Sessions"), th.fg("muted", "esc"), inner)),
      pad(search),
      pad(""),
      ...body,
      ...Array(Math.max(0, height - body.length)).fill(pad("")),
      pad(""),
    ]
  }

  invalidate() {
    this.input.invalidate?.()
  }
}

export default function sessions(pi: Pi) {
  pi.registerCommand("sessions", {
    description: "Switch session (opencode-style picker)",
    handler: async (_args, ctx) => {
      const list = ((await SessionManager.list(ctx.cwd)) as Session[]).sort((a, b) => b.modified.getTime() - a.modified.getTime())
      if (list.length === 0) return ctx.ui.notify("No sessions in this folder", "info")
      const current = ctx.sessionManager.getSessionFile()
      let removeBackdrop = () => {}
      const path = await ctx.ui.custom<string | undefined>(
        (tui, theme, _keys, done) => {
          removeBackdrop = installBackdrop(tui, theme)
          return new Picker(list, current, tui, theme, done)
        },
        { overlay: true, overlayOptions: { width: "60%", minWidth: 60, maxHeight: "70%", anchor: "center" } },
      ).finally(() => removeBackdrop())
      if (path && path !== current) await ctx.switchSession(path)
    },
  })
}
