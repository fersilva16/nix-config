// opencode-style status above the prompt: one line per activity with a
// scanning block spinner, the label, elapsed time or progress, and the key
// that stops it on the right. Covers omo's working, retry, compaction and
// branch-summary indicators and running tool hooks; queued steering and
// follow-up messages are listed above it. The terminal title carries the
// session name and a busy dot.
import { basename } from "node:path"
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import { CHROME } from "./core/card.ts"
import { onQueuedMessages, onStatusLine, onTerminalTitle, type QueuedMessages, type StatusSnapshot } from "./core/host.ts"
import { clock, spread } from "./core/style.ts"
import type { Theme } from "./core/types.ts"

type Pi = {
  on(event: "session_start" | "agent_start" | "agent_settled", handler: (event: unknown, ctx: { ui: Ui }) => void): void
}
type Ui = { theme: Theme; setTitle(title: string | undefined): void }

const TOKEN: Record<string, string> = { working: "accent", retry: "warning", compaction: "accent", branchSummary: "accent" }
const CELLS = 8

// A block that sweeps back and forth, with a fading tail (opencode's scanner).
function scanner(theme: Theme, token: string, now = Date.now()): string {
  const period = (CELLS - 1) * 2
  const step = Math.floor(now / 90) % period
  const head = step < CELLS ? step : period - step
  return Array.from({ length: CELLS }, (_, i) => {
    const d = Math.abs(i - head)
    return d === 0 ? theme.fg(token, "■") : d === 1 ? theme.fg("muted", "■") : theme.fg("dim", "⬝")
  }).join("")
}

// omo's messages carry their own "(esc to cancel)" hints and "..." ellipses;
// the key goes on the right instead.
function label(message: string): string {
  return message
    .replace(/;\s*\S+ to cancel\)/, ")")
    .replace(/\s*\([^()]*\bto (?:cancel|interrupt)\)\s*$/, "")
    .replaceAll("...", "")
    .trim()
}

function line(theme: Theme, width: number, spin: string, text: string, detail: string, hint: string): string {
  const right = hint ? `${hint} ` : ""
  const tail = detail ? `  ${theme.fg("muted", detail)}` : ""
  const left = truncateToWidth(` ${spin}  ${text}${tail}`, Math.max(1, width - visibleWidth(right) - 2), theme.fg("dim", "…"))
  return spread(left, right, width)
}

function drawStatus(theme: Theme, status: StatusSnapshot, width: number): string[] {
  const key = (verb: string) => `${theme.bold(status.interruptKey)} ${theme.fg("muted", verb)}`
  const rows = [""]
  const { indicator } = status
  if (indicator) {
    const token = TOKEN[indicator.kind] ?? "accent"
    const progress = indicator.progress?.replace(/\s+/g, " ").trim() ?? ""
    const tail = progress.length > 60 ? `…${progress.slice(-60)}` : progress
    const detail = indicator.elapsedSeconds !== undefined ? clock(indicator.elapsedSeconds) : tail
    const verb = indicator.kind === "working" ? "interrupt" : "cancel"
    rows.push(line(theme, width, scanner(theme, token), theme.fg("text", label(indicator.message)), detail, key(verb)))
  }
  for (const [i, hook] of status.hooks.entries()) {
    const spin = indicator || i > 0 ? " ".repeat(CELLS) : scanner(theme, "muted")
    const text = `${theme.fg("muted", `${hook.name} hook`)}${hook.message ? theme.fg("dim", ` · ${hook.message}`) : ""}`
    rows.push(line(theme, width, spin, text, clock(hook.elapsedSeconds), ""))
  }
  return rows
}

function drawQueue(theme: Theme, queued: QueuedMessages, width: number): string[] {
  const bar = theme.fg("dim", CHROME.thin)
  const row = (tag: string, text: string) =>
    truncateToWidth(` ${bar} ${tag} ${theme.fg("muted", text.replace(/\s+/g, " ").trim())}`, width, theme.fg("dim", "…"))
  return [
    "",
    ...queued.steering.map((m) => row(theme.bold(theme.fg("accent", "STEER ")), m)),
    ...queued.followUp.map((m) => row(theme.bold(theme.fg("warning", "QUEUED")), m)),
    ` ${bar} ${theme.fg("dim", " ".repeat(6))} ${theme.bold(queued.dequeueKey)} ${theme.fg("muted", "edit queued")}`,
  ]
}

export default function status(pi: Pi) {
  let theme: Theme | undefined
  let busy = false
  onStatusLine((s, width) => (theme ? drawStatus(theme, s, width) : []))
  onQueuedMessages((queued) => ({
    invalidate() {},
    render: (width) => (theme ? drawQueue(theme, queued, width) : []),
  }))
  onTerminalTitle(({ name, cwd }) => `${busy ? "● " : ""}${name ? `${name} · ` : ""}${basename(cwd)} · OmO`)

  // setTitle(undefined) hands the title back to omo, which asks the hook.
  const setBusy = (value: boolean, ui: Ui) => {
    busy = value
    ui.setTitle(undefined)
  }
  pi.on("session_start", (_e, ctx) => {
    theme = ctx.ui.theme
    setBusy(false, ctx.ui)
  })
  pi.on("agent_start", (_e, ctx) => setBusy(true, ctx.ui))
  pi.on("agent_settled", (_e, ctx) => setBusy(false, ctx.ui))
}
