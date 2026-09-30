// Compact rows for built-in, MCP and omo plugin tools, in the style of the compact eval
// row: one header line (status mark, tool, key argument, badges) and a few
// output lines. ctrl+o (expanded) hands back to the tool's own renderer.
// read/grep/find/ls keep omo's renderers, since omo only groups rows that do;
// their groups are drawn with compactLine instead (see tools.ts).
import { truncateToWidth } from "@earendil-works/pi-tui"
import { header, lines, statusMark } from "./codemode.ts"
import type { RowRenderers, RowSnapshot } from "./core/host.ts"
import { homePath, paint, stripAnsi } from "./core/style.ts"
import type { Component, Theme } from "./core/types.ts"
import { isPluginTool, PLUGIN_TOOLS } from "./plugins.ts"

const MAX_OUTPUT_LINES = 3
const TOOLS = new Set([
  "write",
  "edit",
  "bash",
  "apply_patch",
  "bash_output",
  "bash_input",
  "bash_resize",
  "kill_bash",
  "monitor",
  "create_goal",
  "update_goal",
  "get_goal",
  "look_at",
  "tool_search",
  "webfetch",
  "web_search",
])
const ARG_KEYS = ["command", "path", "file_path", "pattern", "query", "url", "objective", "status", "bash_id", "description", "tool", "name"]

type Args = Record<string, unknown>
type Result = NonNullable<RowSnapshot["result"]>
type Context = { args: Args; cwd: string; expanded: boolean; hasResult: boolean; isError: boolean; spinnerFrame?: number; lastComponent?: unknown }
type Options = { expanded: boolean; isPartial: boolean }
type Status = "pending" | "error" | "complete"
// What a finished, successful call adds to its header and below it. Tools
// without a spec show their first output lines.
type Spec = {
  arg(args: Args, cwd: string): string
  done?(result: Result, args: Args, theme: Theme): { badges?: string[]; output?: string[] }
  failed?(result: Result): boolean
}

export function isCompactTool(toolName: string): boolean {
  return TOOLS.has(toolName) || toolName.startsWith("mcp_") || isPluginTool(toolName)
}

const str = (value: unknown): string => (typeof value === "string" ? value : "")
const count = (n: number, one: string, many = `${one}s`): string => `${n} ${n === 1 ? one : many}`
const lineCount = (body: string): number => body.replace(/\n$/, "").split("\n").length

function shortPath(path: string, cwd: string): string {
  return path.startsWith(`${cwd}/`) ? path.slice(cwd.length + 1) : homePath(path)
}

const filePath = (args: Args, cwd: string): string => shortPath(str(args.path) || str(args.file_path), cwd)

function text(result: Result): string {
  return (result.content ?? [])
    .filter((p) => p.type === "text" && p.audience !== "model")
    .map((p) => p.text ?? "")
    .join("\n")
    .trimEnd()
}

// Tool output is drawn in a single colour, so its own escapes and control
// characters (tabs, carriage returns) are dropped to keep widths right.
function clean(line: string): string {
  return stripAnsi(line).replaceAll("\t", "  ").replace(/[\x00-\x1f\x7f]/g, "")
}

function preview(theme: Theme, body: string, from: "head" | "tail" = "head", tone = "toolOutput"): string[] {
  if (!body) return []
  const all = body.split("\n")
  const shown = (from === "head" ? all.slice(0, MAX_OUTPUT_LINES) : all.slice(-MAX_OUTPUT_LINES)).map((l) => theme.fg(tone, clean(l)))
  const rest = all.length - shown.length
  if (rest === 0) return shown
  const more = theme.fg("dim", `… ${rest} ${from === "head" ? "more" : "earlier"} lines · ctrl+o`)
  return from === "head" ? [...shown, more] : [more, ...shown]
}

function editDiff(result: Result, theme: Theme): { badges: string[]; output: string[] } {
  const changed = str(result.details?.diff)
    .split("\n")
    .filter((l) => l.startsWith("+") || l.startsWith("-"))
  const added = changed.filter((l) => l.startsWith("+")).length
  const shown = changed.slice(0, MAX_OUTPUT_LINES).map((l) => theme.fg(l.startsWith("+") ? "toolDiffAdded" : "toolDiffRemoved", clean(l)))
  const rest = changed.length - shown.length
  return {
    badges: [`+${added} -${changed.length - added}`],
    output: rest > 0 ? [...shown, theme.fg("dim", `… ${rest} more changed lines · ctrl+o`)] : shown,
  }
}

function patchFiles(patch: string, cwd: string): string {
  const files = [...patch.matchAll(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm)].map((m) => shortPath(m[1].trim(), cwd))
  return files.length > 2 ? `${files.slice(0, 2).join(", ")} +${files.length - 2}` : files.join(", ")
}

function genericArg(args: Args): string {
  const key = ARG_KEYS.find((k) => typeof args[k] === "string") ?? Object.keys(args).find((k) => typeof args[k] === "string")
  return key ? str(args[key]) : ""
}

const within = (args: Args, cwd: string): string => (str(args.path) ? `in ${shortPath(str(args.path), cwd)}` : "")

const SPECS: Record<string, Spec> = {
  read: {
    arg: (args, cwd) => {
      const offset = typeof args.offset === "number" ? args.offset : undefined
      const limit = typeof args.limit === "number" ? args.limit : undefined
      const from = offset ?? 1
      const range = offset === undefined && limit === undefined ? "" : `:${from}${limit === undefined ? "" : `-${from + limit - 1}`}`
      return filePath(args, cwd) + range
    },
    done: (result) => {
      const body = text(result)
      return { badges: [body.startsWith("Read image file") ? "image" : count(lineCount(body), "line")] }
    },
  },
  write: {
    arg: filePath,
    done: (_result, args) => ({ badges: [count(lineCount(str(args.content)), "line")] }),
  },
  edit: { arg: filePath, done: (result, _args, theme) => editDiff(result, theme) },
  grep: {
    arg: (args, cwd) => [JSON.stringify(str(args.pattern)), within(args, cwd), str(args.glob)].filter(Boolean).join(" "),
    done: (result, _args, theme) => {
      const matches = result.details?.matchCount
      const files = result.details?.fileCount
      const badges = typeof matches === "number" && typeof files === "number" ? [count(matches, "match", "matches"), count(files, "file")] : []
      return { badges, output: preview(theme, text(result)) }
    },
  },
  find: {
    arg: (args, cwd) => [str(args.pattern), within(args, cwd)].filter(Boolean).join(" "),
    done: (result, _args, theme) => {
      const body = text(result)
      return { badges: body ? [count(lineCount(body), "result")] : [], output: preview(theme, body) }
    },
  },
  ls: {
    arg: (args, cwd) => (str(args.path) ? shortPath(str(args.path), cwd) : "."),
    done: (result, _args, theme) => {
      const body = text(result)
      return { badges: body ? [count(lineCount(body), "entry", "entries")] : [], output: preview(theme, body) }
    },
  },
  bash: {
    arg: (args) => str(args.command),
    done: (result, args, theme) => ({ badges: args.run_in_background ? ["background"] : [], output: preview(theme, text(result), "tail") }),
  },
  apply_patch: { arg: (args, cwd) => patchFiles(str(args.input), cwd) },
  tool_search: {
    arg: (args) => str(args.query),
    done: (result) => ({ badges: Array.isArray(result.details?.matched) ? [count(result.details.matched.length, "tool")] : [] }),
  },
}

function specOf(toolName: string): Spec {
  const plugin = PLUGIN_TOOLS[toolName]
  if (SPECS[toolName] || !plugin) return SPECS[toolName] ?? { arg: genericArg }
  const { badges, failed } = plugin
  const details = (result: Result): Args => result.details ?? {}
  return {
    arg: (args, cwd) => plugin.arg(args, (path) => shortPath(path, cwd)),
    done: badges && ((result, args, theme) => ({ badges: badges(details(result), args), output: preview(theme, text(result)) })),
    failed: failed && ((result) => failed(details(result))),
  }
}

export const BACKGROUND: Record<Status, string> = { pending: "toolPendingBg", error: "toolErrorBg", complete: "toolSuccessBg" }

// The padded box omo draws around a row's content: a blank line above and
// below and one column each side, on the row's background.
export function boxLines(theme: Theme, token: string, content: string[], width: number): string[] {
  const pad = paint(theme, token, "", width)
  const inner = Math.max(1, width - 2)
  return [pad, ...content.map((line) => paint(theme, token, ` ${truncateToWidth(line, inner)}`, width)), pad]
}

// One call as a single header line, for the rows of an exploration group.
export function compactLine(call: RowSnapshot, theme: Theme, spinnerFrame: number): string {
  const spec = specOf(call.toolName)
  const status: Status = !call.result || call.isPartial ? "pending" : call.result.isError ? "error" : "complete"
  const badges = call.result && status === "complete" ? (spec.done?.(call.result, call.args, theme).badges ?? []) : []
  return header(theme, statusMark(status, theme, spinnerFrame), call.toolName, spec.arg(call.args, call.cwd), badges)
}

// Components this module handed out. omo passes a row's last component back
// to its renderer, so when ctrl+o switches to the tool's own renderer, it
// must not receive one of these as its own.
const ours = new WeakSet<object>()
const own = (component: Component): Component => (ours.add(component), component)
const theirs = (context: Context): Context => (ours.has(context.lastComponent as object) ? { ...context, lastComponent: undefined } : context)

export function compactRow(original: RowRenderers, toolName: string) {
  const spec = specOf(toolName)
  // Tools with a "self" shell (edit) draw their own box, so their compact
  // rows paint the box omo draws around everyone else's.
  const draw = (theme: Theme, status: Status, build: () => string[]): Component =>
    own(original.renderShell === "self" ? { render: (width) => boxLines(theme, BACKGROUND[status], build(), width), invalidate() {} } : lines(build))

  const renderCall = (args: Args, theme: Theme, context: Context): Component => {
    if (context.expanded) {
      if (original.renderCall) return original.renderCall(args, theme, theirs(context))
      return own(lines(() => [theme.fg("toolTitle", theme.bold(`${toolName} ${spec.arg(args, context.cwd)}`.trim()))]))
    }
    if (context.hasResult) return own(lines(() => []))
    return draw(theme, "pending", () => [header(theme, statusMark("pending", theme, context.spinnerFrame), toolName, spec.arg(args, context.cwd), [])])
  }

  const renderResult = (result: Result, options: Options, theme: Theme, context: Context): Component => {
    if (options.expanded || context.expanded) {
      if (original.renderResult) return original.renderResult(result, options, theme, theirs(context))
      return own(lines(() => text(result).split("\n").map((l) => theme.fg("toolOutput", clean(l)))))
    }
    const status: Status = options.isPartial ? "pending" : context.isError || spec.failed?.(result) ? "error" : "complete"
    const body = text(result)
    const done = status === "complete" ? (spec.done?.(result, context.args, theme) ?? { output: preview(theme, body) }) : {}
    const output = status === "error" ? preview(theme, body, "head", "error") : status === "pending" ? preview(theme, body, "tail") : (done.output ?? [])
    return draw(theme, status, () => [
      header(theme, statusMark(status, theme, context.spinnerFrame), toolName, spec.arg(context.args, context.cwd), done.badges ?? []),
      ...output.map((line) => `  ${line}`),
    ])
  }

  return { renderCall, renderResult }
}
