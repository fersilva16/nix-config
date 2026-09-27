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
