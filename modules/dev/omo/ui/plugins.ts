// omo plugin surfaces (omo.js, omo-task.js, omo-member.js, omo-computer-use.js)
// drawn like the built-in ones. The renderer and row hooks each hold a single
// slot, so this file only supplies tables: entries.ts draws the transcript
// cards and tools.ts the compact rows.

// Messages and entries whose plugin renderer builds omo's notice box (title,
// reason, extra lines through theme.fg), which entries.ts turns into a card.
export const PLUGIN_MESSAGES = ["senpi-task.completion", "senpi-task.team-member-liveness", "omo-fallback-architect:notice"]
export const PLUGIN_ENTRIES = [
  "omo-memorian:gate",
  "omo-memorian:nudged",
  "omo-memorian:recall",
  "omo-kibitzer:recall",
  "omo-kibitzer:nudged",
  "omo-kibitzer:unavailable",
  "senpi-memory.reflection-completion",
  "senpi-memory.reflection-parked",
  "senpi-memory.health",
  "omo-memory:soul-updated",
  "senpi-memory.session-binding",
]

// Messages with no notice box: omo would draw a raw "[customType]" box (no
// renderer) or plain lines. Their text content becomes the card's body.
export const TEXT_MESSAGES: Record<string, { title: string; tone: string }> = {
  "import-repro": { title: "Imported session", tone: "warning" },
  "omo-model-profile:applied": { title: "Model profile applied", tone: "accent" },
  "senpi-task.category-unavailable": { title: "Category unavailable", tone: "warning" },
}

type Args = Record<string, unknown>

const str = (value: unknown): string => (typeof value === "string" ? value : "")
const join = (...parts: unknown[]): string => parts.map(str).filter(Boolean).join(" ")

// lsp_* tools take a file and a 1-based line.
function lspTarget(args: Args, shortPath: (path: string) => string): string {
  const file = str(args.filePath) ? shortPath(str(args.filePath)) : ""
  const at = file && typeof args.line === "number" ? `${file}:${args.line}` : file
  return join(at, args.query, args.newName && `→ ${str(args.newName)}`)
}

const FAILED_TASK = new Set(["error", "lost", "cancelled", "interrupted"])
// The task tools report outcomes like "capacity_deferred" in details.kind.
const kind = (details: Args): string[] => (str(details.kind) ? [str(details.kind).replaceAll("_", " ")] : [])

// A plugin tool's compact row (see rows.ts): the key argument, badges from
// the result's details, and whether the result reports a failure the tool
// did not flag as an error (a task that failed to start returns normally).
type PluginTool = {
  arg(args: Args, shortPath: (path: string) => string): string
  badges?(details: Args, args: Args): string[]
  failed?(details: Args): boolean
}

export const PLUGIN_TOOLS: Record<string, PluginTool> = {
  task: {
    arg: (args) => {
      const batch = Array.isArray(args.tasks) ? `${args.tasks.length} tasks` : ""
      return join(str(args.task_summary) || str(args.description) || str(args.name) || batch, args.category ?? args.subagent_type)
    },
    badges: (details, args) => [
      str(details.status) === "completed" ? "" : str(details.status),
      details.run_in_background || args.run_in_background ? "background" : "",
    ].filter(Boolean),
    failed: (details) => FAILED_TASK.has(str(details.status)),
  },
  task_output: { arg: (args) => join(str(args.name) || str(args.task_id), args.mode), badges: kind },
  task_send: { arg: (args) => join(args.to && `→ ${str(args.to)}`, args.summary), badges: kind },
  task_cancel: { arg: (args) => join(str(args.name) || str(args.task_id), args.reason), badges: kind },
  workpool: { arg: (args) => join(args.op, str(args.name) || str(args.pool_id), Array.isArray(args.items) ? `${args.items.length} items` : "") },
  memory: { arg: (args) => join(args.command, str(args.file_path) || str(args.new_path)) },
  lsp_diagnostics: {
    arg: lspTarget,
    badges: (details) => (typeof details.totalDiagnostics === "number" ? [`${details.totalDiagnostics} diagnostics`] : []),
  },
  lsp_goto_definition: { arg: lspTarget },
  lsp_find_references: { arg: lspTarget },
  lsp_symbols: { arg: lspTarget },
  lsp_prepare_rename: { arg: lspTarget },
  lsp_rename: { arg: lspTarget },
  ask_user_question: {
    arg: (args) => {
      const questions = Array.isArray(args.questions) ? (args.questions as Args[]) : []
      const first = str(questions[0]?.header) || str(questions[0]?.question)
      return questions.length > 1 ? `${first} +${questions.length - 1}` : first
    },
    badges: (details) => (str(details.status) ? [str(details.status)] : []),
  },
}

// Plugin tools without a spec of their own, drawn with the generic one (first
// string argument).
const GENERIC = [
  "task_create",
  "task_list",
  "task_get",
  "task_update",
  "team_create",
  "team_delete",
  "workflow",
  "nudge",
  "session_entries",
  "x_search",
  "thread_create",
  "thread_list",
  "thread_read",
  "thread_send",
  "thread_interrupt",
  "thread_handoff",
  "thread_rename",
  "thread_set_model",
  "thread_set_reasoning",
  "computer",
  "computer_actions",
]

export function isPluginTool(toolName: string): boolean {
  return toolName in PLUGIN_TOOLS || GENERIC.includes(toolName)
}
