// opencode-style prompt: a filled card with an accent bar on the left and an
// "agent · model provider · thinking" line in place of the bottom border.
import { CustomEditor } from "@code-yeongyu/senpi"
import { CURSOR_MARKER, truncateToWidth } from "@earendil-works/pi-tui"
import { type CardStyle, cardInner, cardRow } from "./core/card.ts"
import { type Intent, Keymap, submitCommand } from "./core/intents.ts"
import { stripAnsi } from "./core/style.ts"
import type { Ctx, Theme } from "./core/types.ts"

const BG = "selectedBg"

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: Ctx & { ui: Ui }) => void): void
  getThinkingLevel(): string
  events: { on(channel: "agents:active", handler: (agent: string) => void): void }
}
type Ui = {
  theme: Theme
  setEditorComponent(factory: (tui: unknown, theme: unknown, keybindings: unknown) => unknown): void
}
type Prompt = {
  getText(): string
  setText(text: string): void
  onSubmit?: (text: string) => void
  forward(data: string): void
}

// opencode-style ctrl+x leader: l opens /sessions, a cycles /agent, y replays
// ctrl+x for omo's own copy.
const INTENTS: Intent<Prompt>[] = [
  { leader: true, key: "l", run: (editor) => submitCommand(editor, "/sessions") },
  { leader: true, key: "a", run: (editor) => submitCommand(editor, "/agent") },
  { leader: true, key: "y", run: (editor, _data, leader) => leader && editor.forward(leader) },
]

// CustomEditor.render swaps the first content line's padding for a "❯"
// marker; skip it and lay out the base Editor directly.
const editorRender: (this: CustomEditor, width: number) => string[] = Object.getPrototypeOf(CustomEditor.prototype).render

function isBorder(line: string): boolean {
  return stripAnsi(line).startsWith("─")
}

export default function prompt(pi: Pi) {
  // Published by the agents extension; stays "OmO" without it.
  let agent = "OmO"
  pi.events.on("agents:active", (name) => {
    agent = name === "omo" ? "OmO" : name
  })
  pi.on("session_start", (_e, ctx) => {
    const theme = ctx.ui.theme
    const style: CardStyle = { bar: theme.fg("accent", "┃"), fill: { theme, token: BG } }
    const info = () => {
      const m = ctx.model
      const thinking = pi.getThinkingLevel()
      return [
        theme.fg("accent", agent),
        m ? `${m.name ?? m.id} ${theme.fg("muted", m.provider ?? "")}` : theme.fg("muted", "no model"),
        thinking === "off" ? "" : theme.fg("warning", thinking),
      ]
        .filter(Boolean)
        .join(theme.fg("dim", " · "))
    }

    class PromptEditor extends CustomEditor implements Prompt {
      declare getText: Prompt["getText"]
      declare setText: Prompt["setText"]
      declare onSubmit: Prompt["onSubmit"]
      contentRows = 0
      keys = new Keymap<Prompt>("ctrl+x", INTENTS)

      handleInput(data: string) {
        this.keys.handle(this, data, (d) => super.handleInput(d))
      }

      forward(data: string) {
        super.handleInput(data)
      }

      render(width: number): string[] {
        const inner = cardInner(width)
        const lines = editorRender.call(this, inner)
        let bottom = lines.length - 1
        while (bottom > 0 && !isBorder(lines[bottom])) bottom--
        this.contentRows = bottom - 1
        const row = (text: string) => cardRow(style, text, width)
        const scrolled = (line: string) => stripAnsi(line).replace(/─/g, "").trim()
        const top = scrolled(lines[0])
        const below = scrolled(lines[bottom])
        return [
          row(top ? theme.fg("dim", `  ${top}`) : ""),
          // omo's layout slicer counts the IME cursor marker (an APC escape)
          // as 5 columns, cutting the row short once the sidebar sits to its
          // right. The block cursor is drawn separately, so drop the marker.
          ...lines.slice(1, bottom).map((line) => row(line.replaceAll(CURSOR_MARKER, ""))),
          row(below ? theme.fg("dim", `  ${below}`) : ""),
          row(truncateToWidth(`  ${info()}`, inner)),
          row(""),
          ...lines.slice(bottom + 1),
        ]
      }

      // render() adds a 1-column bar and two rows after the base Editor's
      // bottom border (info line, padding); map clicks back to the base
      // layout [top, content x n, bottom, autocomplete...] so cursor and
      // autocomplete clicks still land.
      handleMouse(event: { x: number; y: number; width: number }) {
        const n = this.contentRows
        const { y } = event
        if (y === n + 2 || y === n + 3) return { handled: true, focus: true }
        const baseY = y <= n + 1 ? y : y - 2
        return super.handleMouse({ ...event, x: event.x - 1, y: baseY, width: Math.max(1, event.width - 1) })
      }
    }

    ctx.ui.setEditorComponent((tui, editorTheme, keybindings) => new PromptEditor(tui, editorTheme, keybindings))
  })
}
