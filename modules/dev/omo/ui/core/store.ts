// Session state shared by the footer, sidebar and prompt: one set of event
// subscriptions keeps it fresh and re-renders the UI when it changes.
import { spawnSync } from "node:child_process"
import { requestRender } from "./host.ts"
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
}

type Pi = {
  on(event: string, handler: (event: unknown, ctx: Ctx) => void): void
  getSessionName(): string | undefined
  events: { on(channel: "agents:active", handler: (agent: string) => void): void }
}

const EDIT_TOOLS = new Set(["edit", "write"])
const REFRESH_EVENTS = ["turn_end", "tool_result", "model_select", "session_info_changed"]

export const store = {
  snapshot: undefined as Snapshot | undefined,
  // Published by the agents extension; stays "OmO" without it.
  agent: "OmO",
}

let pi: Pi | undefined
let branch = ""

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
  }
}

export function refresh(ctx: Ctx): void {
  store.snapshot = collect(ctx)
  requestRender()
}

export function initStore(api: Pi): void {
  pi = api
  api.events.on("agents:active", (name) => {
    store.agent = name === "omo" ? "OmO" : name
  })
  api.on("session_start", (_e, ctx) => {
    branch = gitBranch(ctx.cwd)
    refresh(ctx)
  })
  for (const event of REFRESH_EVENTS) api.on(event, (_e, ctx) => refresh(ctx))
  api.on("agent_settled", (_e, ctx) => {
    branch = gitBranch(ctx.cwd)
    refresh(ctx)
  })
}
