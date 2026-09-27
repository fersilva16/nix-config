// The ask-user question drawn as part of the prompt, as opencode does: the
// prompt's card (bar and fill) with a "Question · <header>" info line and the
// key hints, instead of omo's separate box between two rules. Non-blocking
// questions take the prompt over too, so there is never a typeable prompt
// while a question waits; esc cancels one and gives the prompt back. omo
// still owns the question's state, keys, timeouts and answers.
import { DynamicBorder } from "@code-yeongyu/senpi"
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import { type CardStyle, card, cardInner, promptStyle } from "./core/card.ts"
import { expandPendingQuestions, onQuestion, onQuestionWidget, type QuestionComponent } from "./core/host.ts"
import { spread } from "./core/style.ts"
import type { Component, Theme } from "./core/types.ts"

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: { ui: { theme: Theme } }) => void): void
}
type MouseEvent = { x: number; y: number; width: number; height?: number }

// Matches the prompt's info line inset.
const INSET = "  "

function infoLines(q: QuestionComponent, theme: Theme, width: number): string[] {
  const { state } = q
  const header = state.activeTabIndex === state.request.questions.length ? "Submit" : state.activeQuestion.header
  const left = [theme.fg("accent", "Question"), header, q.countdownLabel && theme.fg("muted", q.countdownLabel)]
    .filter(Boolean)
    .join(theme.fg("dim", " · "))
  const hints = q.hintsText.text
  const oneLine = spread(`${INSET}${left}`, `${hints}${INSET}`, width)
  if (visibleWidth(INSET + left + hints + INSET) + 3 <= width) return [oneLine]
  return [truncateToWidth(`${INSET}${left}`, width), truncateToWidth(`${INSET}${hints}`, width)]
}

// omo's layout is [rule, blank, title, tabs, question, options…, submit,
// hints, blank, rule]. The rules and title go, the hints move to the info
// line, and the blanks become the card's padding like the prompt's.
function frameQuestion(q: QuestionComponent, theme: Theme, style: CardStyle): void {
  q.children = q.children.filter((c) => !(c instanceof DynamicBorder) && c !== q.titleText && c !== q.hintsText)
  const render = q.render.bind(q)
  const handleMouse = q.handleMouse?.bind(q) as ((event: MouseEvent) => unknown) | undefined
  let bodyRows = 0
  q.render = (width) => {
    const inner = cardInner(width)
    const body = render(inner)
    bodyRows = body.length
    return card(style, [...body, ...infoLines(q, theme, inner), ""], width)
  }
  // Clicks on the bar or the info rows are swallowed; the rest are shifted
  // past the bar into omo's own layout.
  q.handleMouse = (event: MouseEvent) => {
    if (event.x < 1 || event.y >= bodyRows) return { handled: true, focus: true }
    return handleMouse?.({ ...event, x: event.x - 1, width: cardInner(event.width), height: bodyRows })
  }
}

// A pending non-blocking question normally takes over the prompt (see
// expandPendingQuestions); while a dialog or another question holds it, the
// widget shows right above the prompt in the same card, so the two read as
// one; the prompt's own top row separates them.
function frameWidget(widget: Component, style: CardStyle): Component {
  const render = widget.render.bind(widget)
  const handleMouse = widget.handleMouse?.bind(widget)
  const offset = 1 + INSET.length
  return Object.assign(widget, {
    render: (width: number) => {
      const inner = cardInner(width)
      const lines = render(Math.max(1, inner - INSET.length)).map((line) => `${INSET}${line}`)
      return card(style, ["", ...lines], width)
    },
    handleMouse: (event: MouseEvent) =>
      handleMouse?.({ ...event, x: event.x - offset, y: event.y - 1, width: Math.max(1, cardInner(event.width) - INSET.length) }),
  })
}

export default function question(pi: Pi) {
  pi.on("session_start", (_e, ctx) => {
    const theme = ctx.ui.theme
    const style = promptStyle(theme)
    onQuestion((q) => frameQuestion(q, theme, style))
    onQuestionWidget((widget) => frameWidget(widget, style))
    expandPendingQuestions()
  })
}
