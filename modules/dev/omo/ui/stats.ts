import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"

export type Theme = {
  fg(token: string, text: string): string
  bg(token: string, text: string): string
  bold(text: string): string
}
type Usage = { cost?: { total?: number } }
export type Block = { type: string; text?: string; name?: string; arguments?: { path?: string } }
export type Entry = {
  type: string
  message?: { role?: string; content?: Block[] | string; usage?: Usage }
}
export type Ctx = {
  cwd: string
  model?: { id: string; name?: string; provider?: string }
  getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined
  sessionManager: { getBranch(): Entry[]; getSessionId(): string }
}

export function sessionCost(entries: Entry[]): number {
  let cost = 0
  for (const e of entries) {
    if (e.type === "message" && e.message?.role === "assistant") cost += e.message.usage?.cost?.total ?? 0
  }
  return cost
}

export function contextUsage(ctx: Ctx): { tokens: number | undefined; percent: number | undefined } {
  const usage = ctx.getContextUsage()
  return { tokens: usage?.tokens ?? undefined, percent: usage?.percent ?? undefined }
}

export function shortTokens(n: number): string {
  return n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}K`
}

export function homePath(path: string): string {
  const home = process.env.HOME
  return home && path.startsWith(home) ? `~${path.slice(home.length)}` : path
}

// theme.bg() closes with \x1b[49m, and styled content inside a line resets
// the background mid-way; re-open it after every reset so the whole row
// stays painted, then pad to `width` so the fill reaches the edge.
export function paint(theme: Theme, token: string, line: string, width: number): string {
  const open = theme.bg(token, "\u0000").split("\u0000")[0]
  const fitted = truncateToWidth(line, width)
  const body = fitted.replaceAll("\x1b[0m", `\x1b[0m${open}`).replaceAll("\x1b[49m", `\x1b[49m${open}`)
  return `${open}${body}${" ".repeat(Math.max(0, width - visibleWidth(fitted)))}\x1b[49m`
}

export function spread(left: string, right: string, width: number): string {
  const gap = width - visibleWidth(left) - visibleWidth(right)
  return gap >= 1 ? `${left}${" ".repeat(gap)}${right}` : truncateToWidth(left, width)
}
