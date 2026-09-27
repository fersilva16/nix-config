// opencode-style tool blocks plus the compact eval renderer. omo has no API
// for restyling rows or replacing another extension's tool renderer, so this
// finds a live ToolExecutionComponent in the render tree and wraps its
// prototype's render (shared by every row). Rows keep their tool definition on
// `identity`, and the host reads renderCall/renderResult from it on each
// render, so swapping them on the eval definition is enough. Like sidebar.ts,
// this touches omo internals.
import { compactEval, type EvalRenderers } from "./codemode.ts"
import type { Ctx, Theme } from "./stats.ts"

const ORIGINAL_RENDER = Symbol.for("omo-ui-tools.render")

type Node = { children?: Node[]; layoutRoot?: Node; constructor: { name: string } }
type Row = Node & {
  isPartial: boolean
  result?: { isError?: boolean }
  identity: { toolName: string; toolCallId: string; toolDefinition?: Partial<EvalRenderers> & { renderShell?: string } }
  render(width: number): string[]
  invalidate(): void
}
type Tui = Node & { requestRender(): void }
type Pi = {
  on(event: string, handler: (event: { toolName?: string; toolCallId?: string }, ctx: Ctx & { ui: Ui }) => void): void
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
type Ui = { setWidget(key: string, factory: (tui: Tui, theme: Theme) => { render(): string[]; invalidate(): void }): void }

function findRow(node: Node | undefined, seen = new Set<Node>()): Row | undefined {
  if (!node || seen.has(node)) return undefined
  seen.add(node)
  if (node.constructor.name === "ToolExecutionComponent") return node as Row
  for (const child of [node.layoutRoot, ...(node.children ?? [])]) {
    const row = findRow(child, seen)
    if (row) return row
  }
  return undefined
}

function blockBackground(row: Row): string {
  if (row.isPartial) return "toolPendingBg"
  return row.result?.isError ? "toolErrorBg" : "toolSuccessBg"
}

export default function tools(pi: Pi) {
  let tui: Tui | undefined
  let theme: Theme | undefined
  let patched = false
  const compacted = new WeakSet<object>()
  const refreshed = new WeakSet<Row>()
  // Every todo call re-prints the whole checklist. Only the latest todo row
  // renders; earlier ones collapse to nothing, so the list reads as one card
  // that updates in place.
  let latestTodo: string | undefined
  const todoRows = new Map<string, Row>()
  const setLatestTodo = (id: string | undefined) => {
    if (id === latestTodo) return
    const previous = latestTodo === undefined ? undefined : todoRows.get(latestTodo)
    latestTodo = id
    previous?.invalidate()
    tui?.requestRender()
  }

  // Rows restored with a session rendered (and cached) before the swap, so
  // each eval row is invalidated once to rebuild with the compact renderer.
  const compact = (row: Row) => {
    const def = row.identity.toolDefinition
    if (row.identity.toolName !== "eval" || !def?.renderCall || !def.renderResult || refreshed.has(row)) return
    if (!compacted.has(def)) {
      Object.assign(def, compactEval({ renderCall: def.renderCall, renderResult: def.renderResult }))
      compacted.add(def)
    }
    refreshed.add(row)
    row.invalidate()
  }

  const patch = () => {
    if (patched || !tui) return
    const row = findRow(tui)
    if (!row) return
    patched = true
    // omo's own render is kept on the prototype under a global symbol so a
    // reloaded copy of this module replaces the wrapper instead of stacking
    // another bar on top.
    const proto = Object.getPrototypeOf(row) as Row & { [ORIGINAL_RENDER]?: Row["render"] }
    const original = (proto[ORIGINAL_RENDER] ??= proto.render)
    proto.render = function (this: Row, width: number) {
      if (this.identity.toolName === "todo") {
        todoRows.set(this.identity.toolCallId, this)
        if (latestTodo !== undefined && this.identity.toolCallId !== latestTodo) return []
      }
      compact(this)
      const lines = original.call(this, Math.max(1, width - 1))
      if (!theme) return lines
      const th = theme
      const bar = th.bg(blockBackground(this), th.fg(this.result?.isError ? "error" : "border", "│"))
      if (lines.length === 0) return lines
      return [...lines.map((line, i) => (i === 0 && line === "" ? line : bar + line)), ""]
    }
    tui.requestRender()
  }

  pi.on("session_start", (_e, ctx) => {
    todoRows.clear()
    setLatestTodo(lastTodoCallId(ctx))
    ctx.ui.setWidget("ui-tools-mount", (t, th) => {
      tui = t
      theme = th
      return {
        render() {
          patch()
          return []
        },
        invalidate() {},
      }
    })
  })
  for (const event of ["tool_call", "tool_result", "turn_end"]) pi.on(event, patch)
  pi.on("tool_call", (e) => {
    if (e.toolName === "todo") setLatestTodo(e.toolCallId)
  })
}
