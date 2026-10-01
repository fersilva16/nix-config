// opencode-style prompt: a filled card with an accent bar on the left and an
// "agent · model provider · thinking" line in place of the bottom border.
import { CustomEditor } from "@code-yeongyu/senpi"
import { truncateToWidth } from "@earendil-works/pi-tui"
import { cardInner, cardRow, promptStyle } from "./core/card.ts"
import { copySelection } from "./core/host.ts"
import { type Intent, Keymap, submitCommand } from "./core/intents.ts"
import { confirm, type ModalCtx } from "./core/modal.ts"
import { fill, sgr, stripAnsi } from "./core/style.ts"
import type { Ctx, Theme } from "./core/types.ts"

type Session = Ctx & { ui: Ui; isIdle(): boolean; abort(): void; shutdown(): void }
type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: Session) => void): void
  getThinkingLevel(): string
  events: {
    on(channel: "agents:active", handler: (agent: string) => void): void
    emit(channel: string, data?: unknown): void
  }
}
type Ui = ModalCtx["ui"] & {
  theme: Theme
  setEditorComponent(factory: (tui: unknown, theme: unknown, keybindings: unknown) => unknown): void
}
type Prompt = {
  getText(): string
  setText(text: string): void
  onSubmit?: (text: string) => void
  forward(data: string): void
  isShowingAutocomplete(): boolean
}

// Key table. Tab on an empty draft cycles the primary agent, as in opencode;
// with text (or an open autocomplete) it stays omo's completion. ctrl+c copies
// a mouse selection, else clears the draft, else exits (asking first while
// the agent works). The ctrl+x leader: l opens /resume, a cycles the agent,
// y replays ctrl+x for omo's own copy.
function intents(pi: Pi, ctx: Session): Intent<Prompt>[] {
  const cycleAgent = () => pi.events.emit("agents:cycle")
  let confirming = false
  const exitOrConfirm = async () => {
    if (ctx.isIdle()) return ctx.shutdown()
    if (confirming) return
    confirming = true
    const choice = await confirm(ctx, {
      title: "Agent is working",
      message: "Exit omo, or interrupt the current run?",
      actions: [
        { key: "ctrl+c", label: "exit", value: "exit" },
        { key: "i", label: "interrupt", value: "interrupt" },
        { key: "escape", label: "stay", value: "stay" },
      ],
    }).finally(() => {
      confirming = false
    })
    if (choice === "exit") ctx.shutdown()
    else if (choice === "interrupt") ctx.abort()
  }
  return [
    { id: "agent.cycle", key: "tab", when: (editor) => editor.getText() === "" && !editor.isShowingAutocomplete(), run: cycleAgent },
    {
      id: "app.exitOrConfirm",
      key: "ctrl+c",
      run: (editor) => {
        if (copySelection()) return
        if (editor.getText() !== "") return editor.setText("")
        void exitOrConfirm()
      },
    },
    { leader: true, key: "l", run: (editor) => submitCommand(editor, "/resume") },
    { id: "agent.cycle", leader: true, key: "a", run: cycleAgent },
    { leader: true, key: "y", run: (editor, _data, leader) => leader && editor.forward(leader) },
  ]
}

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
    const style = promptStyle(theme)
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
      suggestionRows = 0
      declare isShowingAutocomplete: Prompt["isShowingAutocomplete"]
      keys = new Keymap<Prompt>("ctrl+x", intents(pi, ctx))

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
        const suggestions = lines.slice(bottom + 1)
        this.suggestionRows = suggestions.length > 0 ? suggestions.length + 1 : 0
        return [
          ...(suggestions.length > 0 ? [row(""), ...suggestions.map((line) => this.suggestion(line, width))] : []),
          row(top ? theme.fg("dim", `  ${top}`) : ""),
          // Rows keep the cursor marker: omo puts the terminal's own cursor
          // there (showHardwareCursor, set in omo.nix) instead of a block.
          ...lines.slice(1, bottom).map(row),
          row(below ? theme.fg("dim", `  ${below}`) : ""),
          row(truncateToWidth(`  ${info()}`, inner)),
          row(""),
        ]
      }

      // omo lists completions (slash commands, @files) under the editor as
      // "→ label   description" rows and an "(i/n)" counter. They are drawn at
      // the top of the card instead, as opencode does: the selected row as
      // an accent bar, descriptions muted.
      suggestion(line: string, width: number): string {
        const text = stripAnsi(line)
        const item = /^\s*(→ |  )(\S.*?)(?:(\s{2,})(.*))?$/.exec(text)
        if (!item) return cardRow(style, theme.fg("dim", `  ${text.trim()}`), width)
        const [, marker, label, gap = "", description = ""] = item
        if (marker.startsWith("→")) {
          const accent = sgr(theme, "accent", "fg", "bg")
          const ink = sgr(theme, "selectedBg", "bg", "fg")
          return style.bar + fill(accent, `  ${ink}\x1b[1m${label}${gap}${description}`, cardInner(width))
        }
        return cardRow(style, `  ${label}${gap}${theme.fg("muted", description)}`, width)
      }

      // render() adds a 1-column bar, the suggestions (plus a padding row)
      // above the card, and two rows after the base Editor's bottom border
      // (info line, padding); map clicks back to the base layout
      // [top, content x n, bottom, autocomplete...] so cursor and
      // autocomplete clicks still land.
      handleMouse(event: { x: number; y: number; width: number }) {
        const n = this.contentRows
        const above = this.suggestionRows
        if (event.y < above) {
          if (event.y === 0) return { handled: true, focus: true }
          return super.handleMouse({ ...event, x: event.x - 1, y: n + 2 + event.y - 1, width: Math.max(1, event.width - 1) })
        }
        const y = event.y - above
        if (y === n + 2 || y === n + 3) return { handled: true, focus: true }
        return super.handleMouse({ ...event, x: event.x - 1, y, width: Math.max(1, event.width - 1) })
      }
    }

    ctx.ui.setEditorComponent((tui, editorTheme, keybindings) => new PromptEditor(tui, editorTheme, keybindings))
  })
}
