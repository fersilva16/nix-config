// opencode-style tool blocks plus the compact eval renderer. omo has no API
// for restyling rows or replacing another extension's tool renderer, so this
// finds a live ToolExecutionComponent in the render tree and wraps its
// prototype's render (shared by every row). Rows keep their tool definition on
// `identity`, and the host reads renderCall/renderResult from it on each
// render, so swapping them on the eval definition is enough. Like sidebar.ts,
// this touches omo internals.
import { compactEval, type EvalRenderers } from "./codemode.ts"
import type { Theme } from "./stats.ts"

type Node = { children?: Node[]; layoutRoot?: Node; constructor: { name: string } }
type Row = Node & {
  isPartial: boolean
  result?: { isError?: boolean }
  identity: { toolName: string; toolDefinition?: Partial<EvalRenderers> & { renderShell?: string } }
  render(width: number): string[]
  invalidate(): void
}
type Tui = Node & { requestRender(): void }
type Pi = {
  on(event: string, handler: (event: unknown, ctx: { ui: Ui }) => void): void
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
    const proto = Object.getPrototypeOf(row) as Row
    const original = proto.render
    proto.render = function (this: Row, width: number) {
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
}
