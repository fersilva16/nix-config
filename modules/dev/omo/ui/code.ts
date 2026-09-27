// Markdown code blocks as cards: a language header, the syntax-highlighted
// code on a filled background, and a bar on the left, instead of omo's ```
// fences. The renderCodeBlock hook lives in core/host.ts.
import { wrapTextWithAnsi } from "@earendil-works/pi-tui"
import { CHROME, type CardStyle, cardInner, cardRow } from "./core/card.ts"
import { onCodeBlock } from "./core/host.ts"
import type { Theme } from "./core/types.ts"

const BG = "userMessageBg"
const PAD = " "

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: { ui: { theme: Theme } }) => void): void
}

// /reload rebuilds the transcript before session_start hands this module the
// theme, and markdown caches what it rendered; keeping the theme under a
// global symbol lets the reloaded copy draw cards on that first render.
const THEME = Symbol.for("omo-ui.code.theme")
const shared = globalThis as { [THEME]?: Theme }

export default function code(pi: Pi) {
  pi.on("session_start", (_e, ctx) => {
    shared[THEME] = ctx.ui.theme
  })

  onCodeBlock(({ lang, width, highlight }) => {
    const theme = shared[THEME]
    if (!theme) return undefined
    const fill = { theme, token: BG }
    const bar = (glyph: string): CardStyle => ({ bar: theme.bg(BG, theme.fg("mdCodeBlockBorder", glyph)), fill })
    // Long lines wrap inside the card (padding on both sides) rather than
    // being cut, so a copied selection still has the whole line.
    const wrap = Math.max(1, cardInner(width) - 2 * PAD.length)
    const rows = highlight().flatMap((line) => (line ? wrapTextWithAnsi(line, wrap) : [""]))
    return [
      cardRow(bar(CHROME.edge), `${PAD}${theme.fg("dim", lang || "text")}`, width),
      ...rows.map((line) => cardRow(bar(CHROME.code), `${PAD}${line}`, width)),
      cardRow(bar(CHROME.edge), "", width),
    ]
  })
}
