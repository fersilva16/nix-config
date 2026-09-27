// opencode-style session picker: /sessions (or ctrl+x l) opens a centred
// dialog listing this folder's sessions grouped by day, newest first, with
// fuzzy search, rename and delete. omo's own /resume stays available for its
// extras (all folders, sort modes). The dimmed backdrop comes from backdrop.ts.
import { spawnSync } from "node:child_process"
import { existsSync, unlinkSync } from "node:fs"
import { SessionManager } from "@earendil-works/pi-coding-agent"
import { fuzzyFilter, Input, Key, matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import { spread, type Theme } from "./stats.ts"

// opencode's "large" dialog: 88 columns, a one-column margin around the
// highlight bar, and text inset three more columns inside it.
const WIDTH = 88
const EDGE = 1
const INDENT = 3
const CHROME = 8 // top pad, title, gap, search, gap, gap, hints, bottom pad

type Session = { path: string; name?: string; firstMessage: string; modified: Date }
type Tui = { requestRender(): void; terminal: { rows: number; columns: number } }
type Ctx = {
  cwd: string
  sessionManager: { getSessionFile(): string | undefined }
  switchSession(path: string): Promise<{ cancelled?: boolean }>
  ui: {
    custom<T>(
      factory: (tui: Tui, theme: Theme, keybindings: unknown, done: (value: T) => void) => unknown,
      options: { overlay: true; overlayOptions: () => Record<string, unknown> },
    ): Promise<T>
    notify(message: string, level: "info" | "warning" | "error"): void
  }
}
type Pi = {
  setSessionName(name: string): void
  registerCommand(name: string, options: { description: string; handler: (args: string, ctx: Ctx) => Promise<void> }): void
}
type Row = { gap: true } | { header: string } | { session: Session; index: number }

const title = (s: Session) => (s.name ?? s.firstMessage).split("\n")[0].trim()
const code = (styled: string) => styled.split("\u0000")[0]

// Paint a row with an arbitrary background, re-opening it after every inner
// reset so styled spans don't punch holes in the fill.
function fill(open: string, line: string, width: number): string {
  const fitted = truncateToWidth(line, width)
  const body = fitted.replaceAll("\x1b[0m", `\x1b[0m${open}`).replaceAll("\x1b[49m", `\x1b[49m${open}`)
  return `${open}${body}${" ".repeat(Math.max(0, width - visibleWidth(fitted)))}\x1b[49m`
}

function dayLabel(date: Date, now: Date): string {
  const day = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  if (day(date) === day(now)) return "Today"
  return date.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" }).replaceAll(",", "")
}

function deleteFile(path: string): string | undefined {
  spawnSync("trash", [path])
  if (!existsSync(path)) return undefined
  try {
    unlinkSync(path)
    return undefined
  } catch (error) {
    return error instanceof Error ? error.message : String(error)
  }
}

class Picker {
  private readonly search = new Input({ prompt: "", placeholder: "Search" })
  private readonly renameInput = new Input({ prompt: "", placeholder: "Session name" })
  private matches: Session[]
  private selected = 0
  private scroll = 0
  private renaming: Session | undefined
  private confirmDelete: string | undefined
  private status: string | undefined
  private readonly listHeight: number
  private _focused = false

  constructor(
    private sessions: Session[],
    private readonly current: string | undefined,
    private readonly pi: Pi,
    private readonly tui: Tui,
    private readonly theme: Theme,
    private readonly done: (path: string | undefined) => void,
  ) {
    this.matches = sessions
    this.selected = Math.max(0, sessions.findIndex((s) => s.path === current))
    this.listHeight = Math.max(3, Math.min(this.rows().length, Math.floor(tui.terminal.rows * 0.75) - CHROME))
  }

  get focused() {
    return this._focused
  }
  set focused(value: boolean) {
    this._focused = value
    this.search.focused = value && !this.renaming
    this.renameInput.focused = value && !!this.renaming
  }

  handleInput(data: string) {
    this.status = undefined
    if (this.renaming) this.handleRename(data)
    else this.handleList(data)
    this.tui.requestRender()
  }

  private handleList(data: string) {
    const session = this.matches[this.selected]
    const confirming = this.confirmDelete
    this.confirmDelete = undefined
    if (matchesKey(data, Key.escape)) return this.done(undefined)
    if (matchesKey(data, Key.enter)) return this.done(session?.path)
    if (matchesKey(data, Key.up) || matchesKey(data, Key.ctrl("p"))) return this.move(-1)
    if (matchesKey(data, Key.down) || matchesKey(data, Key.ctrl("n"))) return this.move(1)
    if (matchesKey(data, Key.ctrl("d"))) {
      if (!session) return
      if (session.path === this.current) this.status = "Can't delete the active session"
      else if (confirming === session.path) this.remove(session)
      else this.confirmDelete = session.path
      return
    }
    if (matchesKey(data, Key.ctrl("r"))) {
      if (!session) return
      this.renaming = session
      this.renameInput.setValue(title(session))
      this.focused = this._focused
      return
    }
    this.search.handleInput(data)
    this.filter()
  }

  private handleRename(data: string) {
    if (matchesKey(data, Key.escape)) return this.stopRenaming()
    if (!matchesKey(data, Key.enter)) return this.renameInput.handleInput(data)
    const session = this.renaming
    const name = this.renameInput.getValue().trim()
    if (session && name) {
      try {
        if (session.path === this.current) this.pi.setSessionName(name)
        else SessionManager.open(session.path).appendSessionInfo(name)
        session.name = name
      } catch (error) {
        this.status = `Rename failed: ${error instanceof Error ? error.message : String(error)}`
      }
    }
    this.stopRenaming()
  }

  private stopRenaming() {
    this.renaming = undefined
    this.focused = this._focused
  }

  private remove(session: Session) {
    const error = deleteFile(session.path)
    if (error) {
      this.status = `Delete failed: ${error}`
      return
    }
    this.sessions = this.sessions.filter((s) => s !== session)
    this.filter()
    this.selected = Math.min(this.selected, Math.max(0, this.matches.length - 1))
  }

  private filter() {
    const hits = new Set(fuzzyFilter(this.sessions, this.search.getValue(), title))
    this.matches = this.sessions.filter((s) => hits.has(s))
    this.selected = 0
    this.scroll = 0
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
      if (label !== last) {
        if (rows.length > 0) rows.push({ gap: true })
        rows.push({ header: label })
      }
      last = label
      rows.push({ session, index })
    })
    return rows
  }

  render(width: number): string[] {
    const th = this.theme
    const bg = code(th.bg("userMessageBg", "\u0000"))
    const paper = bg.replace("[48;", "[38;")
    const inset = EDGE + INDENT
    const inner = Math.max(1, width - 2 * inset)
    const line = (text = "") => fill(bg, `${" ".repeat(inset)}${truncateToWidth(text, inner)}`, width)
    const bar = (open: string, text: string) =>
      fill(bg, `${" ".repeat(EDGE)}${fill(open, `${" ".repeat(INDENT)}${truncateToWidth(text, inner)}`, width - 2 * EDGE)}`, width)

    const rows = this.rows()
    const height = this.listHeight
    const at = rows.findIndex((r) => "session" in r && r.index === this.selected)
    // Keep the selected row visible, and its day header when it is the first of its group.
    const top = at > 0 && "header" in rows[at - 1] ? at - 1 : at
    if (top >= 0 && top < this.scroll) this.scroll = top
    if (at >= this.scroll + height) this.scroll = at - height + 1

    const body = rows.slice(this.scroll, this.scroll + height).map((row) => {
      if ("gap" in row) return line()
      if ("header" in row) return line(th.fg("mdHeading", th.bold(row.header)))
      const { session, index } = row
      if (index !== this.selected) return line(title(session))
      if (this.confirmDelete === session.path) {
        return bar(code(th.fg("error", "\u0000")).replace("[38;", "[48;"), `${paper}\x1b[1mPress ctrl+d again to confirm`)
      }
      return bar(code(th.fg("mdLink", "\u0000")).replace("[38;", "[48;"), `${paper}\x1b[1m${truncateToWidth(title(session), inner)}`)
    })
    if (rows.length === 0) body.push(line(th.fg("muted", "No matching sessions")))

    const key = (label: string, keys: string) => `${label} ${th.fg("muted", keys)}`
    const hints = this.renaming
      ? [key("save", "enter"), key("cancel", "esc")].join("   ")
      : [key("delete", "ctrl+d"), key("rename", "ctrl+r")].join("   ")
    const input = this.renaming ? this.renameInput : this.search

    return [
      line(),
      line(spread(th.bold(this.renaming ? "Rename session" : "Sessions"), th.fg("muted", "esc"), inner)),
      line(),
      line(input.render(inner)[0] ?? ""),
      line(),
      ...body,
      ...Array.from({ length: Math.max(0, height - body.length) }, () => line()),
      line(),
      line(this.status ? th.fg("error", this.status) : hints),
      line(),
    ]
  }

  invalidate() {
    this.search.invalidate?.()
    this.renameInput.invalidate?.()
  }
}

export default function sessions(pi: Pi) {
  pi.registerCommand("sessions", {
    description: "Switch session (opencode-style picker)",
    handler: async (_args, ctx) => {
      const list = ((await SessionManager.list(ctx.cwd)) as Session[]).sort((a, b) => b.modified.getTime() - a.modified.getTime())
      if (list.length === 0) return ctx.ui.notify("No sessions in this folder", "info")
      const current = ctx.sessionManager.getSessionFile()
      let columns = WIDTH + 4
      const path = await ctx.ui.custom<string | undefined>(
        (tui, theme, _keys, done) => {
          columns = tui.terminal.columns
          return new Picker(list, current, pi, tui, theme, done)
        },
        { overlay: true, overlayOptions: () => ({ width: Math.min(WIDTH, columns - 4), anchor: "center" }) },
      )
      if (path && path !== current) await ctx.switchSession(path)
    },
  })
}
