// Compact codemode (eval) rows. Collapsed: one status line plus the nested
// tool calls and the first output lines. ctrl+o (expanded) hands back to codemode's
// own renderer, so the full code/output view is one key away.
import { truncateToWidth } from "@earendil-works/pi-tui"
import type { Theme } from "./stats.ts"

const MAX_CALLS = 4
const MAX_OUTPUT_LINES = 3
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
const ARG_KEYS = ["command", "path", "file_path", "pattern", "query", "url", "description", "prompt", "name"]

type Component = { render(width: number): string[]; invalidate(): void }
type ToolCall = { name: string; ok: boolean; error?: string; args?: unknown }
type Cell = { summary?: string; language: string; output: string; status: string; durationMs?: number; startedAt?: number }
type Details = {
  action?: string
  language?: string
  summary?: string
  durationMs?: number
  wallDurationMs?: number
  toolCallCount?: number
  toolCalls?: ToolCall[]
  isError?: boolean
  cells?: Cell[]
  jsonOutputs?: unknown[]
}
type Result = { content: { type: string; text?: string; audience?: string }[]; details?: Details }
type Args = { language?: string; summary?: string; action?: string }
type Context = { args: Args; expanded: boolean; hasResult: boolean; isError: boolean; spinnerFrame?: number }
type RenderCall = (args: Args, theme: Theme, context: Context) => Component
type RenderResult = (result: Result, options: { expanded: boolean; isPartial: boolean }, theme: Theme, context: Context) => Component
export type EvalRenderers = { renderCall: RenderCall; renderResult: RenderResult }

function lines(render: (width: number) => string[]): Component {
  return { render: (width) => render(width).map((line) => truncateToWidth(line, width)), invalidate() {} }
}

function duration(ms: number | undefined): string {
  if (ms === undefined) return ""
  if (ms < 1000) return "<1s"
  const s = Math.floor(ms / 1000)
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`
}

function argPreview(args: unknown): string {
  if (typeof args !== "object" || args === null) return ""
  const record = args as Record<string, unknown>
  const key = ARG_KEYS.find((k) => typeof record[k] === "string")
  const text = key ? String(record[key]) : JSON.stringify(args)
  return text.replace(/\s+/g, " ")
}

function statusMark(status: string, theme: Theme, frame: number | undefined): string {
  switch (status) {
    case "complete":
      return theme.fg("success", "✓")
    case "error":
      return theme.fg("error", "✗")
    case "cancelled":
      return theme.fg("error", "×")
    case "detached":
      return theme.fg("warning", "↗")
    default:
      return theme.fg("warning", SPINNER[(frame ?? 0) % SPINNER.length])
  }
}

function header(theme: Theme, mark: string, language: string, summary: string | undefined, badges: string[]): string {
  const dot = theme.fg("dim", " · ")
  const title = `${mark} ${theme.bold(language)}`
  return [summary ? `${title} ${theme.fg("muted", summary.split("\n")[0])}` : title, ...badges.map((b) => theme.fg("dim", b))].join(dot)
}

export function compactEval(original: EvalRenderers): EvalRenderers {
  const renderCall: RenderCall = (args, theme, context) => {
    if (context.expanded || args.action !== undefined) return original.renderCall(args, theme, context)
    if (context.hasResult) return lines(() => [])
    return lines(() => [header(theme, statusMark("pending", theme, context.spinnerFrame), args.language ?? "eval", args.summary, [])])
  }

  const renderResult: RenderResult = (result, options, theme, context) => {
    const details = result.details
    if (options.expanded || context.expanded || details === undefined || details.action !== undefined) {
      return original.renderResult(result, options, theme, context)
    }
    const cell = details.cells?.[0]
    const status = cell?.status ?? (details.isError || context.isError ? "error" : options.isPartial ? "running" : "complete")
    const live = status === "running" || status === "pending"
    const elapsed = live && cell?.startedAt !== undefined ? Date.now() - cell.startedAt : (details.wallDurationMs ?? details.durationMs)
    const calls = details.toolCalls ?? []
    const callCount = details.toolCallCount ?? calls.length
    const badges = [callCount > 0 ? `${callCount} call${callCount === 1 ? "" : "s"}` : "", duration(elapsed)].filter(Boolean)
    const isError = status === "error" || status === "cancelled"

    const output = (
      cell?.output ??
      result.content
        .filter((p) => p.type === "text" && p.audience !== "model")
        .map((p) => p.text ?? "")
        .join("\n")
    ).trimEnd()

    return lines(() => {
      const out = [
        header(theme, statusMark(status, theme, context.spinnerFrame), cell?.language ?? details.language ?? "eval", cell?.summary ?? details.summary ?? context.args.summary, badges),
      ]
      const shown = calls.slice(-MAX_CALLS)
      if (calls.length > shown.length) out.push(theme.fg("dim", `  … ${calls.length - shown.length} earlier calls`))
      for (const call of shown) {
        const mark = call.ok ? theme.fg("success", "✓") : theme.fg("error", "✗")
        const error = call.error ? theme.fg("error", ` — ${call.error.split("\n")[0]}`) : ""
        out.push(`  ${mark} ${call.name} ${theme.fg("muted", argPreview(call.args))}${error}`)
      }
      if (output) {
        const all = output.split("\n")
        const head = all.slice(0, MAX_OUTPUT_LINES)
        for (const line of head) out.push(`  ${theme.fg(isError ? "error" : "toolOutput", line)}`)
        if (all.length > head.length) out.push(theme.fg("dim", `  … ${all.length - head.length} more lines · ctrl+o`))
      }
      const displays = details.jsonOutputs?.length ?? 0
      if (displays > 0) out.push(theme.fg("dim", `  ${displays} display value${displays === 1 ? "" : "s"} · ctrl+o`))
      return out
    })
  }

  return { renderCall, renderResult }
}
