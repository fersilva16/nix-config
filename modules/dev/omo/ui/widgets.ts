// Widgets other extensions set around the prompt, as cards instead of raw
// lines: omo-task's running subagents and omo-dag's run progress below the
// editor, and prompt-url's notice above it. omo still owns their content and
// their updates; only the frame and the colouring change.
import { truncateToWidth } from "@earendil-works/pi-tui"
import { card, type CardStyle, CHROME, cardInner } from "./core/card.ts"
import { onWidgetContent } from "./core/host.ts"
import { stripAnsi } from "./core/style.ts"
import type { Component, Theme, Tui } from "./core/types.ts"

const BG = "customMessageBg"
const PAD = " "
// Widgets whose content is one plain line per task, dag run or dag node.
const PROGRESS = ["omo-task", "omo-dag"]

// omo-task's spinner frames and the state glyphs omo-dag draws for a run and
// its nodes. A line's leading glyph gives it its colour.
const SPINNER = new Set(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
const GLYPHS: Record<string, string> = {
  "▶": "accent",
  "◌": "muted",
  "◔": "muted",
  "⊟": "warning",
  "✓": "success",
  "✗": "error",
  "⊘": "muted",
  "⏸": "warning",
  // A paused dag run.
  "·": "warning",
}

function cardStyle(theme: Theme): CardStyle {
  return { bar: theme.bg(BG, theme.fg("accent", CHROME.thin)), fill: { theme, token: BG } }
}

// A progress line: "⠋ summary · category · running · 1m 4s" for a task,
// "▶ run running wave 1/3 2/7 done" or "  ▶ node · agent:x · 3s" for a dag,
// "name|category mode completed" for a finished background task and a
// "+N more" tail. The glyph carries the colour, everything from the first
// separator on is metadata and is muted, and a line with no glyph is done or
// a count, so it is muted whole.
function progressLine(theme: Theme, raw: string): string {
  const text = stripAnsi(raw)
  const body = text.trimStart()
  const indent = " ".repeat(text.length - body.length)
  const glyph = [...body][0] ?? ""
  const tone = SPINNER.has(glyph) ? "accent" : GLYPHS[glyph]
  const rest = tone ? body.slice(glyph.length) : body
  const cut = rest.search(/ · |\|/)
  const head = cut === -1 ? rest : rest.slice(0, cut)
  const tail = cut === -1 ? "" : theme.fg("muted", rest.slice(cut))
  return `${indent}${tone ? theme.fg(tone, glyph) : ""}${tone ? head : theme.fg("muted", head)}${tail}`
}

// The lines are fitted to the terminal's full width, which is wider than the
// transcript column the card sits in, so they are truncated rather than
// wrapped: what falls off the end is the metadata tail. A blank line above
// parts the card from the prompt and from the other progress card.
function progressCard(lines: string[], theme: Theme): Component {
  return {
    render(width) {
      const inner = Math.max(1, cardInner(width) - 2 * PAD.length)
      const rows = lines.map((line) => PAD + truncateToWidth(progressLine(theme, line), inner))
      return ["", ...card(cardStyle(theme), ["", ...rows, ""], width)]
    },
    invalidate() {},
  }
}

export default function widgets() {
  for (const key of PROGRESS) {
    onWidgetContent(key, (content) =>
      Array.isArray(content) ? (_tui: Tui, theme: Theme) => progressCard(content, theme) : content,
    )
  }
  // prompt-url's notice box is already padded on the card's background, so it
  // only gains the bar, and a blank line below parts it from the prompt as
  // /btw's card does.
  onWidgetContent("prompt-url", (content) =>
    typeof content !== "function"
      ? content
      : (tui: Tui, theme: Theme): Component => {
          const box = content(tui, theme)
          return {
            render: (width) => [...card(cardStyle(theme), box.render(cardInner(width)), width), ""],
            invalidate: () => box.invalidate(),
          }
        },
  )
}
