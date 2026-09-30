// opencode's transcript look for the entries omo draws itself: user messages
// as a filled card with the prompt's accent bar, thinking dimmed behind a
// thin bar with no blank lines, `!cmd` runs as tool cards, summaries and
// skill invocations as notice cards, and turn errors and inline notices as
// cards like entries.ts draws. The hooks live in core/host.ts.
import { CHROME, card, cardInner } from "./core/card.ts"
import { onThinkingBlock, onTranscriptEntry, onTranscriptNotice, type TranscriptEntry } from "./core/host.ts"
import { stripAnsi } from "./core/style.ts"
import type { Theme } from "./core/types.ts"
import { type Line, noticeCard } from "./entries.ts"

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: { ui: { theme: Theme } }) => void): void
}

type BashStatus = Extract<TranscriptEntry, { kind: "bash" }>["status"]
const BASH_BG: Record<BashStatus, string> = {
  running: "toolPendingBg",
  complete: "toolSuccessBg",
  error: "toolErrorBg",
  cancelled: "toolErrorBg",
}

// omo labels summaries "[compaction]", "[branch]" and "[skill]"; the card
// titles them instead, padded to the label's width so the filled row keeps
// its length.
function retitle(lines: string[], kind: string): string[] {
  const label = `[${kind}]`
  const title = (kind[0].toUpperCase() + kind.slice(1)).padEnd(label.length)
  const at = lines.findIndex((line) => line.includes(label))
  return at < 0 ? lines : lines.with(at, lines[at].replace(label, title))
}

export default function transcript(pi: Pi) {
  let theme: Theme | undefined
  pi.on("session_start", (_e, ctx) => {
    theme = ctx.ui.theme
  })

  onTranscriptEntry((entry, render, width) => {
    const t = theme
    if (!t) return render(width)
    const inner = cardInner(width)
    switch (entry.kind) {
      case "user": {
        const bar = t.fg("accent", CHROME.bar)
        return render(inner).map((line) => bar + line)
      }
      case "bash": {
        const bg = BASH_BG[entry.status]
        const style = { bar: t.bg(bg, t.fg(entry.status === "error" ? "error" : "border", CHROME.thin)), fill: { theme: t, token: bg } }
        return ["", ...card(style, ["", ...render(inner), ""], width)]
      }
      default: {
        const bar = t.bg("customMessageBg", t.fg("customMessageLabel", CHROME.thin))
        return retitle(render(inner), entry.kind).map((line) => bar + line)
      }
    }
  })

  onThinkingBlock((part, render, width) => {
    const t = theme
    if (!t) return render(width)
    const bar = t.fg("thinkingText", CHROME.thin)
    const lines = render(cardInner(width))
    return (part === "body" ? lines.filter((line) => stripAnsi(line).trim()) : lines).map((line) => bar + line)
  })

  // /reload rebuilds the transcript before session_start hands over the
  // theme, so the card reads it when drawn rather than when added.
  onTranscriptNotice((notice) => ({
    render(width) {
      const t = theme
      if (!t) return [notice.text]
      const lines: Line[] =
        notice.tone === "error"
          ? [
              { tone: "error", text: t.bold("Error") },
              { tone: "text", text: notice.text },
            ]
          : [{ tone: notice.tone, text: notice.text }]
      return noticeCard(lines, t).render(width)
    },
    invalidate() {},
  }))
}
