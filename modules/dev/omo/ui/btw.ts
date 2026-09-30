// omo's /btw side answer as a card above the prompt, instead of a block
// between two rules: a thin accent bar on a filled background holding the
// question, the streaming answer and omo's hint line. omo still owns the
// side query, the streaming, esc and dismissal.
import { CHROME, card, cardInner } from "./core/card.ts"
import { onWidgetContent } from "./core/host.ts"
import type { Component } from "./core/types.ts"

const BG = "customMessageBg"

export default function btw() {
  onWidgetContent("btw", (content) =>
    typeof content !== "function"
      ? content
      : (tui, theme): Component => {
          const panel = content(tui, theme)
          const style = { bar: theme.bg(BG, theme.fg("accent", CHROME.thin)), fill: { theme, token: BG } }
          return {
            // omo's panel is [rule, text, rule]; the rules go and the card
            // pads the text instead.
            render: (width) => [...card(style, ["", ...panel.render(cardInner(width)).slice(1, -1), ""], width), ""],
            invalidate: () => panel.invalidate(),
          }
        },
  )
}
