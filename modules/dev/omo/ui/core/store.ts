// Session state shared by the footer and sidebar: one set of event
// subscriptions keeps it fresh and re-renders the UI when it changes.
import { spawnSync } from "node:child_process"
import { type Notice, requestRender } from "./host.ts"
import type { Ctx, Entry } from "./types.ts"

export type Snapshot = {
  title: string
  sessionId: string
  tokens: number | undefined
  percent: number | undefined
  cost: number
  files: string[]
  cwd: string
  branch: string
  todos: TodoPhase[]
}

export type TodoTask = { content: string; status: string }
export type TodoPhase = { name: string; tasks: TodoTask[] }
// omo's todo_owed_reminder event: the model was reminded of open todos
// ("delivered"), or gave up after the last reminder ("capped").
export type TodoOwed = { chainCount: number; openTasks: number; reason: "delivered" | "capped" }

type Pi = {
  on(event: string, handler: (event: unknown, ctx: Ctx) => void): void
  getSessionName(): string | undefined
  events: { on(channel: "todo_owed_reminder", handler: (event: TodoOwed) => void): void }
}

const EDIT_TOOLS = new Set(["edit", "write"])
const REFRESH_EVENTS = ["turn_end", "tool_result", "model_select", "session_info_changed"]

export const store = {
  snapshot: undefined as Snapshot | undefined,
  // Transcript notices the sidebar took over (core/host.ts onNotice), newest last.
  notices: [] as Notice[],
  // A newer omo release, from the update check.
  update: undefined as string | undefined,
  // Whether omo's per-model optimized system prompt is applied.
  promptOptimized: false,
  todoOwed: undefined as TodoOwed | undefined,
}

let pi: Pi | undefined
let branch = ""
let live: Ctx | undefined

export function sessionCost(entries: Entry[]): number {
  let cost = 0
  for (const e of entries) {
    if (e.type === "message" && e.message?.role === "assistant") cost += e.message.usage?.cost?.total ?? 0
  }
  return cost
}

export function contextUsage(ctx: Ctx): { tokens: number | undefined; percent: number | undefined } {
  const usage = ctx.getContextUsage()
  return { tokens: usage?.tokens ?? undefined, percent: usage?.percent ?? undefined }
}

function firstUserText(entries: Entry[]): string {
  for (const e of entries) {
    const m = e.message
    if (e.type !== "message" || m?.role !== "user") continue
    const text = typeof m.content === "string" ? m.content : m.content?.find((b) => b.type === "text")?.text
    if (typeof text === "string" && text.trim()) return text.trim().split("\n")[0]
  }
  return "New session"
}

function gitBranch(cwd: string): string {
  const r = spawnSync("git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8" })
  return r.status === 0 ? r.stdout.trim() : ""
}

// The todo list as omo's todo extension persists it: the latest
// senpi.todo-state entry or todo tool result on the branch wins.
function latestTodos(entries: Entry[]): TodoPhase[] {
  let phases: TodoPhase[] = []
  for (const e of entries) {
    const m = e.message
    const payload =
      e.type === "custom" && e.customType === "senpi.todo-state"
        ? e.data
        : e.type === "message" && m?.role === "toolResult" && (m.toolName === "todo" || m.toolName === "todowrite")
          ? m.details
          : undefined
    const next = (payload as { phases?: unknown } | undefined)?.phases
    if (Array.isArray(next)) phases = next as TodoPhase[]
  }
  return phases
}

function collect(ctx: Ctx): Snapshot {
  const entries = ctx.sessionManager.getBranch()
  const files = new Set<string>()
  for (const e of entries) {
    const m = e.message
    if (e.type !== "message" || m?.role !== "assistant" || !Array.isArray(m.content)) continue
    for (const b of m.content) {
      if (b.type === "toolCall" && EDIT_TOOLS.has(b.name ?? "") && b.arguments?.path) files.add(b.arguments.path)
    }
  }
  const cwdPrefix = ctx.cwd.endsWith("/") ? ctx.cwd : `${ctx.cwd}/`
  return {
    title: pi?.getSessionName() ?? firstUserText(entries),
    sessionId: ctx.sessionManager.getSessionId(),
    ...contextUsage(ctx),
    cost: sessionCost(entries),
    files: [...files].map((f) => (f.startsWith(cwdPrefix) ? f.slice(cwdPrefix.length) : f)),
    cwd: ctx.cwd,
    branch,
    todos: latestTodos(entries),
  }
}

export function refresh(ctx: Ctx): void {
  live = ctx
  store.snapshot = collect(ctx)
  requestRender()
}

// For changes that arrive without a ctx (a /todo edit re-syncing omo's
// widget). No-op between session_shutdown and the next session_start.
export function refreshLive(): void {
  if (live) refresh(live)
}

export function initStore(api: Pi): void {
  pi = api
  api.events.on("todo_owed_reminder", (event) => {
    store.todoOwed = event
    requestRender()
  })
  // omo resets its reminder chain on user input; so does the marker.
  api.on("input", () => {
    store.todoOwed = undefined
  })
  api.on("session_shutdown", () => {
    live = undefined
  })
  api.on("session_start", (_e, ctx) => {
    store.todoOwed = undefined
    branch = gitBranch(ctx.cwd)
    refresh(ctx)
  })
  for (const event of REFRESH_EVENTS) api.on(event, (_e, ctx) => refresh(ctx))
  api.on("agent_settled", (_e, ctx) => {
    branch = gitBranch(ctx.cwd)
    refresh(ctx)
  })
}
