// opencode-style prompt: a filled box with an accent bar on the left and an
// "agent · model provider · thinking" line in place of the bottom border.
import { CustomEditor } from "@code-yeongyu/senpi"
import { CURSOR_MARKER, truncateToWidth } from "@earendil-works/pi-tui"
import { type Ctx, paint, type Theme } from "./stats.ts"

const BG = "selectedBg"
const ANSI = /\x1b\[[0-9;]*m/g

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: Ctx & { ui: Ui }) => void): void
  getThinkingLevel(): string
}
type Ui = {
  theme: Theme
  setEditorComponent(factory: (tui: unknown, theme: unknown, keybindings: unknown) => unknown): void
}

// CustomEditor.render swaps the first content line's padding for a "❯"
// marker; skip it and lay out the base Editor directly.
const editorRender: (this: CustomEditor, width: number) => string[] = Object.getPrototypeOf(CustomEditor.prototype).render

function isBorder(line: string): boolean {
  return line.replace(ANSI, "").startsWith("─")
}

export default function prompt(pi: Pi) {
  pi.on("session_start", (_e, ctx) => {
    const theme = ctx.ui.theme
    const info = () => {
      const m = ctx.model
      const thinking = pi.getThinkingLevel()
      return [
        theme.fg("accent", "OmO"),
        m ? `${m.name ?? m.id} ${theme.fg("muted", m.provider ?? "")}` : theme.fg("muted", "no model"),
        thinking === "off" ? "" : theme.fg("warning", thinking),
      ]
        .filter(Boolean)
        .join(theme.fg("dim", " · "))
    }

    class PromptEditor extends CustomEditor {
      contentRows = 0

      render(width: number): string[] {
        const inner = Math.max(1, width - 1)
        const lines = editorRender.call(this, inner)
        let bottom = lines.length - 1
        while (bottom > 0 && !isBorder(lines[bottom])) bottom--
        this.contentRows = bottom - 1
        const bar = theme.fg("accent", "┃")
        const row = (text: string) => bar + paint(theme, BG, text, inner)
        const scrolled = (line: string) => line.replace(ANSI, "").replace(/─/g, "").trim()
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
