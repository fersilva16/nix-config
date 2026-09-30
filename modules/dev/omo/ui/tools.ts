// opencode-style tool blocks (a card bar on each row) plus the compact eval
// renderer. The row hooks live in core/host.ts.
import { compactEval, type EvalRenderers } from "./codemode.ts"
import { CHROME, cardInner, cardRow } from "./core/card.ts"
import { onExplorationGroup, onToolRow, replaceToolRenderers, replaceToolRenderersWhere, requestRender, type ToolRow } from "./core/host.ts"
import type { Ctx, Theme } from "./core/types.ts"
import { BACKGROUND, boxLines, compactLine, compactRow, isCompactTool } from "./rows.ts"

const MAX_GROUP_LINES = 8
const SPINNER_FRAME_MS = 80

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
  replaceToolRenderersWhere(isCompactTool, compactRow)
  onToolRow((row, render, width) => {
    if (row.identity.toolName === "todo") {
      todoRows.set(row.identity.toolCallId, row)
      if (latestTodo !== undefined && row.identity.toolCallId !== latestTodo) return []
    }
    const lines = render(cardInner(width))
    if (!theme || lines.length === 0) return lines
    const style = { bar: theme.bg(blockBackground(row), theme.fg(row.result?.isError ? "error" : "border", CHROME.thin)) }
    return [...lines.map((line, i) => (i === 0 && line === "" ? line : cardRow(style, line, width))), ""]
  })
  // A run of read/grep/find/ls calls: one card with a compact line per call.
  onExplorationGroup((calls, rules, width) => {
    if (!theme) return undefined
    const t = theme
    const status = calls.some((c) => c.isPartial || !c.result) ? "pending" : "complete"
    const frame = Math.floor(Date.now() / SPINNER_FRAME_MS)
    const body = calls.map((call) => compactLine(call, t, frame))
    if (rules > 0) body.push(t.fg("dim", `applied ${rules} project rule${rules === 1 ? "" : "s"}`))
    const shown = body.length > MAX_GROUP_LINES ? [...body.slice(0, MAX_GROUP_LINES), t.fg("dim", `… ${body.length - MAX_GROUP_LINES} more · ctrl+o`)] : body
    const failed = calls.some((c) => c.result?.isError)
    const style = { bar: t.bg(BACKGROUND[status], t.fg(failed ? "error" : "border", CHROME.thin)) }
    return ["", ...boxLines(t, BACKGROUND[status], shown, cardInner(width)).map((line) => cardRow(style, line, width)), ""]
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
