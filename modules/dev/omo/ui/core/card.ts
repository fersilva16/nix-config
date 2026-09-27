// A card: content with a one-column bar on its left edge, optionally on a
// filled background. Tool rows and the prompt are cards.
import { paint } from "./style.ts"
import type { Theme } from "./types.ts"

export type CardStyle = { bar: string; fill?: { theme: Theme; token: string } }

export function cardInner(width: number): number {
  return Math.max(1, width - 1)
}

export function cardRow(style: CardStyle, text: string, width: number): string {
  const { bar, fill } = style
  return bar + (fill ? paint(fill.theme, fill.token, text, cardInner(width)) : text)
}

export function card(style: CardStyle, lines: string[], width: number): string[] {
  return lines.map((line) => cardRow(style, line, width))
}

// Glyphs reserved for card chrome. A copied selection drops them (see
// stripChrome), so none may be something omo draws as content: markdown
// tables and quotes use │, so cards never do.
export const CHROME = {
  // The prompt's accent bar.
  bar: "┃",
  // Tool rows.
  thin: "▏",
  // Code block rows.
  code: "▎",
  // Rows that are chrome as a whole (a code block's language header and
  // bottom padding): a copied row that starts with it is dropped.
  edge: "▍",
} as const

const BAR_AT_START = new RegExp(`^(\\s*[${CHROME.bar}${CHROME.thin}${CHROME.code}]) ?`)

function indent(row: string): number {
  return row.trim() ? row.length - row.trimStart().length : Number.POSITIVE_INFINITY
}

// Rewrites copied text: drops edge rows, removes a leading bar with the
// margin before it and the space after it, then dedents. Cards sit at
// different insets than the text around them, so each run of rows under one
// bar is dedented on its own (keeping a code block's relative indentation),
// and the rows without a bar share one dedent. The first row is left out of
// that shared indent when others exist, since a selection may start mid-row.
export function stripChrome(text: string): string {
  let run = 0
  let previous: string | undefined
  const rows = text
    .split("\n")
    .filter((row) => !row.trimStart().startsWith(CHROME.edge))
    .map((row) => {
      const bar = BAR_AT_START.exec(row)
      if (bar && bar[1] !== previous) run++
      previous = bar?.[1]
      return bar ? { text: row.slice(bar[0].length), group: `card ${run}` } : { text: row, group: "text" }
    })
  const shared = new Map<string, number>()
  rows.forEach(({ text, group }, i) => {
    const skip = i === 0 && group === "text" && rows.slice(1).some((r) => r.group === "text" && r.text.trim())
    if (!skip) shared.set(group, Math.min(shared.get(group) ?? Number.POSITIVE_INFINITY, indent(text)))
  })
  return rows.map(({ text, group }) => text.slice(Math.min(shared.get(group) ?? 0, indent(text)))).join("\n")
}
