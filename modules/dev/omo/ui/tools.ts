// opencode-style tool blocks (a card bar on each row) plus the compact eval
// renderer. The row hooks live in core/host.ts.
import { compactEval, type EvalRenderers } from "./codemode.ts"
import { cardInner, cardRow } from "./core/card.ts"
import { onToolRow, replaceToolRenderers, requestRender, type ToolRow } from "./core/host.ts"
import type { Ctx, Theme } from "./core/types.ts"

type Pi = {
  on(event: string, handler: (event: { toolName?: string; toolCallId?: string }, ctx: Ctx & { ui: { theme: Theme } }) => void): void
}

function lastTodoCallId(ctx: Ctx): string | undefined {
  let id: string | undefined
  for (const e of ctx.sessionManager.getBranch()) {
    const content = e.message?.role === "assistant" ? e.message.content : undefined
    if (!Array.isArray(content)) continue
    for (const b of content) if (b.type === "toolCall" && b.name === "todo") id = b.id
  }
  return id
}

function blockBackground(row: ToolRow): string {
  if (row.isPartial) return "toolPendingBg"
  return row.result?.isError ? "toolErrorBg" : "toolSuccessBg"
}

export default function tools(pi: Pi) {
  let theme: Theme | undefined
  // Every todo call re-prints the whole checklist. Only the latest todo row
  // renders; earlier ones collapse to nothing, so the list reads as one card
  // that updates in place.
  let latestTodo: string | undefined
  const todoRows = new Map<string, ToolRow>()
  const setLatestTodo = (id: string | undefined) => {
    if (id === latestTodo) return
    const previous = latestTodo === undefined ? undefined : todoRows.get(latestTodo)
    latestTodo = id
    previous?.invalidate()
    requestRender()
  }

  replaceToolRenderers("eval", (original) => compactEval(original as EvalRenderers))
  onToolRow((row, render, width) => {
    if (row.identity.toolName === "todo") {
      todoRows.set(row.identity.toolCallId, row)
      if (latestTodo !== undefined && row.identity.toolCallId !== latestTodo) return []
    }
    const lines = render(cardInner(width))
    if (!theme || lines.length === 0) return lines
    const style = { bar: theme.bg(blockBackground(row), theme.fg(row.result?.isError ? "error" : "border", "│")) }
    return [...lines.map((line, i) => (i === 0 && line === "" ? line : cardRow(style, line, width))), ""]
  })

  pi.on("session_start", (_e, ctx) => {
    theme = ctx.ui.theme
    todoRows.clear()
    setLatestTodo(lastTodoCallId(ctx))
  })
  pi.on("tool_call", (e) => {
    if (e.toolName === "todo") setLatestTodo(e.toolCallId)
  })
}
