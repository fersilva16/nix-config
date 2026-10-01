// Shared text and colour helpers: escape handling, background fills, layout
// and number formatting.
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import type { Theme } from "./types.ts"

// Every escape omo emits: CSI (colours, cursor), OSC (hyperlinks) and APC
// (the IME cursor marker, which ends in BEL).
export const ESCAPES = /\x1b\[[0-9;:?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b_[^\x07\x1b]*(?:\x07|\x1b\\)/g
export const ESCAPE_AT_START = new RegExp(`^(?:${ESCAPES.source})`)

export function stripAnsi(text: string): string {
  return text.replace(ESCAPES, "")
}

// The raw SGR sequence a theme token opens with, optionally moved to the other
// layer (a foreground colour used as a background, or the reverse).
export function sgr(theme: Theme, token: string, layer: "fg" | "bg", as: "fg" | "bg" = layer): string {
  const open = theme[layer](token, "\u0000").split("\u0000")[0]
  return layer === as ? open : open.replace(layer === "fg" ? "[38;" : "[48;", as === "fg" ? "[38;" : "[48;")
}

// Styled spans inside a line reset the background mid-way; re-open it after
// every reset so the whole row stays painted, then pad to `width`.
export function fill(open: string, line: string, width: number): string {
  const fitted = truncateToWidth(line, width)
  const body = fitted.replaceAll("\x1b[0m", `\x1b[0m${open}`).replaceAll("\x1b[49m", `\x1b[49m${open}`)
  return `${open}${body}${" ".repeat(Math.max(0, width - visibleWidth(fitted)))}\x1b[49m`
}

export function paint(theme: Theme, token: string, line: string, width: number): string {
  return fill(sgr(theme, token, "bg"), line, width)
}

export function spread(left: string, right: string, width: number): string {
  const gap = width - visibleWidth(left) - visibleWidth(right)
  return gap >= 1 ? `${left}${" ".repeat(gap)}${right}` : truncateToWidth(left, width)
}

export function clock(seconds: number): string {
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`
}

export function shortTokens(n: number): string {
  return n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}K`
}

export function homePath(path: string): string {
  const home = process.env.HOME
  return home && path.startsWith(home) ? `~${path.slice(home.length)}` : path
}
