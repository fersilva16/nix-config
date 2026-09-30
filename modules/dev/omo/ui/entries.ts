// Notices omo's built-in extensions add to the transcript (loop guard,
// terminal restore digest, /ir import, cache warm pings, /loop ticks, rule
// activations, MCP authorization) drawn as cards like tool rows, instead of
// omo's padded notice box. The renderer hook lives in core/host.ts.
import { wrapTextWithAnsi } from "@earendil-works/pi-tui"
import { CHROME, type CardStyle, card, cardInner } from "./core/card.ts"
import { type CustomRenderer, onCustomRenderer } from "./core/host.ts"
import type { Block, Component, Theme } from "./core/types.ts"

const BG = "customMessageBg"
const PAD = " "

const MESSAGES = new Set(["loop-guard:notice", "loop-guard:escalation", "senpi-terminal:restore-digest", "import-repro"])
const ENTRIES = new Set(["cache-keepalive", "goal-cache-warmup", "loop-tick", "rule-activation", "mcp-auth"])

// A card line: text and the theme token it is coloured with. The first line
// is the title, and its tone colours the card's bar.
type Line = { tone: string; text: string }

// omo's notice renderers build their box from a title, a reason and extra
// lines, colouring each with theme.fg as they go. Running one against a theme
// that records those calls yields the lines in order.
function capture(render: CustomRenderer, item: never, options: { expanded: boolean }, theme: Theme) {
  const lines: Line[] = []
  const recording = new Proxy(theme, {
    get(target, key) {
      if (key === "fg")
        return (tone: string, text: string) => {
          lines.push({ tone, text })
          return target.fg(tone, text)
        }
      const value = Reflect.get(target, key)
      return typeof value === "function" ? value.bind(target) : value
    },
  })
  return { component: render(item, options, recording), lines }
}

function noticeCard(lines: Line[], theme: Theme): Component {
  const style: CardStyle = { bar: theme.bg(BG, theme.fg(lines[0].tone, CHROME.thin)), fill: { theme, token: BG } }
  return {
    render(width) {
      const wrap = Math.max(1, cardInner(width) - 2 * PAD.length)
      const rows = lines.flatMap((line) => wrapTextWithAnsi(theme.fg(line.tone, line.text), wrap)).map((row) => PAD + row)
      return card(style, ["", ...rows, ""], width)
    },
    invalidate() {},
  }
}

// /ir's platform notice has no renderer of its own; omo would draw it as a
// raw "[import-repro]" box.
function importRepro(message: { content: string | Block[] }, _options: unknown, theme: Theme): Component {
  const content = message.content
  const text = typeof content === "string" ? content : content.flatMap((b) => (b.type === "text" && b.text ? [b.text] : [])).join("\n")
  return noticeCard([{ tone: "warning", text: theme.bold("Imported session") }, { tone: "dim", text }], theme)
}

export default function entries() {
  onCustomRenderer((kind, customType, original) => {
    if (!(kind === "message" ? MESSAGES : ENTRIES).has(customType)) return undefined
    if (!original) return customType === "import-repro" ? importRepro : undefined
    return (item, options, theme) => {
      const { component, lines } = capture(original, item, options, theme)
      return component && lines.length > 0 ? noticeCard(lines, theme) : component
    }
  })
}
