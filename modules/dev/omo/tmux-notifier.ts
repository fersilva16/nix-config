// omo port of modules/dev/opencode-manager/plugins/tmux-notifier.ts. Same
// contract with tmux-opencode-manager: @oc-sid/@oc-status/@oc-dir pane options
// drive the bar colour and the session picker, and `notify add` feeds the
// prefix+N queue. Only the event source differs: senpi's agent lifecycle
// instead of opencode's session.* bus. The OPENCODE_TMUX_NOTIFIER_* knobs are
// shared, so one switch mutes both agents.
import { spawn, spawnSync } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { basename } from "node:path"

type EventKind = "complete" | "permission" | "error" | "question"

// The slice of senpi's ExtensionAPI this file touches.
export type Ctx = {
  cwd: string
  isIdle(): boolean
  sessionManager: { getSessionId(): string; getSessionFile(): string | null | undefined }
}
export type RunMessage = { role?: string; stopReason?: string }
export type Pi = {
  cwd: string
  sessionKind: "interactive" | "worker"
  on(event: "session_start" | "agent_start" | "agent_settled" | "session_shutdown", handler: (event: unknown, ctx: Ctx) => void): void
  on(event: "agent_end", handler: (event: { messages?: RunMessage[] }, ctx: Ctx) => void): void
  on(event: "session_info_changed", handler: (event: { name?: string }, ctx: Ctx) => void): void
  events: {
    on(channel: "herdr:blocked", handler: (payload: { active?: boolean; label?: string }) => void): void
    on(channel: "wake_source_state", handler: (payload: { source?: string; activeCount?: number }) => void): void
  }
}

const CMD = "tmux-opencode-manager"
const TMUX_PANE = process.env.TMUX_PANE ?? ""
const SOUND_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_SOUND !== "0"
const DESKTOP_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_DESKTOP !== "0"
const BG_FILTER_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_BG_FILTER !== "0"
const SOUND_DIR = process.env.OPENCODE_TMUX_NOTIFIER_SOUND_DIR ?? ""

function numberEnv(name: string, fallback: number, max: number): number {
  const n = Number(process.env[name] ?? NaN)
  return Number.isFinite(n) && n >= 0 && n <= max ? n : fallback
}
const IDLE_DELAY_MS = numberEnv("OPENCODE_TMUX_NOTIFIER_IDLE_DELAY_MS", 1500, Infinity)
const VOLUME = numberEnv("OPENCODE_TMUX_NOTIFIER_VOLUME", 0.7, 1)

const MAC_SOUNDS: Record<EventKind, string> = {
  complete: "/System/Library/Sounds/Glass.aiff",
  permission: "/System/Library/Sounds/Ping.aiff",
  error: "/System/Library/Sounds/Basso.aiff",
  question: "/System/Library/Sounds/Tink.aiff",
}

function runDetached(cmd: string, args: string[]) {
  try {
    const proc = spawn(cmd, args, { stdio: "ignore", detached: true })
    proc.on("error", () => {})
    proc.unref()
  } catch {
    // Notifier side-effects must never break the omo session.
  }
}

// Synchronous for the same reason as the opencode plugin: pane options are the
// pane's identity, and an unordered 'idle' landing after a 'busy' parks it on
// the wrong state.
function setPaneOption(option: string, value: string): boolean {
  try {
    const res = spawnSync("tmux", ["set-option", "-p", "-t", TMUX_PANE, option, value], {
      stdio: "ignore",
      timeout: 300,
    })
    return !res.error && res.status === 0
  } catch {
    return false
  }
}

function isPaneFocusedInAttachedClient(): boolean {
  try {
    const res = spawnSync("tmux", ["display-message", "-p", "-t", TMUX_PANE, "#{window_active} #{session_attached}"], {
      encoding: "utf8",
      timeout: 300,
    })
    const [active, attached] = (res.stdout ?? "").trim().split(/\s+/)
    return res.status === 0 && active === "1" && Number(attached) > 0
  } catch {
    return false
  }
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content
  if (!Array.isArray(content)) return ""
  return content.map((p: { text?: unknown }) => (typeof p?.text === "string" ? p.text : "")).join("")
}

// Background `task` launches still waiting on their completion wake. The
// parent ends its turn while children run in the shared RPC host, which this
// extension instance cannot observe, so the transcript is the only record.
export function pendingBackgroundTasks(jsonl: string): Set<string> {
  const launched = new Set<string>()
  const finished = new Set<string>()
  for (const line of jsonl.split("\n")) {
    if (!line.includes("st_")) continue
    let entry: { type?: string; customType?: string; content?: unknown; message?: { role?: string; toolName?: string; content?: unknown } }
    try {
      entry = JSON.parse(line)
    } catch {
      continue
    }
    const msg = entry.message
    if (entry.type === "message" && msg?.role === "toolResult" && msg.toolName === "task") {
      for (const m of textOf(msg.content).matchAll(/\((st_[A-Za-z0-9]+), running\)/g)) launched.add(m[1])
    } else if (entry.type === "custom_message" && entry.customType === "omo-senpi:wake") {
      const text = textOf(entry.content)
      const id = text.startsWith("task completion") ? /\bid:(st_[A-Za-z0-9]+)/.exec(text)?.[1] : undefined
      if (id) finished.add(id)
    }
  }
  for (const id of finished) launched.delete(id)
  return launched
}

export default function (pi: Pi) {
  // Worker sessions (subagents) run in the shared RPC host, whose TMUX_PANE
  // belongs to whichever pane happened to start it.
  if (pi.sessionKind !== "interactive" || !TMUX_PANE) return

  const projectName = basename(pi.cwd)
  let sessionID = ""
  let sessionName = ""
  let lastRun: "ok" | "error" | "cancelled" = "ok"
  let pendingComplete: ReturnType<typeof setTimeout> | undefined
  // Things that will wake this session on their own: monitors, background
  // bash sessions, detached eval cells, DAG runs... as omo publishes them on
  // its event bus (the same feed its herdr status reporter reads). A pending
  // ask-user question is the user's move, so it does not hold the pane busy.
  const wakeSources = new Map<string, number>()
  let heldCtx: Ctx | undefined

  const suffix = () => (sessionName ? `: ${sessionName}` : ` (${projectName})`)

  function dispatch(event: EventKind, body: string) {
    if (isPaneFocusedInAttachedClient()) return
    const args = ["notify", "add", "--event", event, "--require-target", "--pane-id", TMUX_PANE]
    if (sessionID) args.push("--session-id", sessionID)
    runDetached(CMD, [...args, body])
    if (SOUND_ENABLED) {
      const custom = `${SOUND_DIR}/${event}.wav`
      runDetached("afplay", ["-v", String(VOLUME), SOUND_DIR && existsSync(custom) ? custom : MAC_SOUNDS[event]])
    }
    if (DESKTOP_ENABLED) {
      const esc = (s: string) => s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
      runDetached("osascript", ["-e", `display notification "${esc(body)}" with title "${esc(projectName)}"`])
    }
  }

  function bind(ctx: Ctx) {
    const id = ctx.sessionManager.getSessionId()
    // Latch only once the claim lands, so a dropped write retries next event.
    if (!id || id === sessionID || !setPaneOption("@oc-sid", id)) return
    sessionID = id
    setPaneOption("@oc-dir", ctx.cwd)
  }

  function cancelPending() {
    clearTimeout(pendingComplete)
    pendingComplete = undefined
  }

  function waitingOnBackgroundTasks(ctx: Ctx): boolean {
    const file = ctx.sessionManager.getSessionFile()
    // ponytail: rereads the whole transcript once per settle; tail-read it if
    // multi-MB sessions ever make settling feel slow.
    return !!file && existsSync(file) && pendingBackgroundTasks(readFileSync(file, "utf8")).size > 0
  }

  pi.on("session_start", (_event, ctx) => {
    cancelPending()
    sessionName = ""
    bind(ctx)
    setPaneOption("@oc-status", "idle")
  })

  pi.on("session_info_changed", (event) => {
    sessionName = event.name ?? ""
  })

  pi.on("agent_start", (_event, ctx) => {
    cancelPending()
    heldCtx = undefined
    bind(ctx)
    setPaneOption("@oc-status", "busy")
  })

  pi.on("agent_end", (event) => {
    const last = [...(event.messages ?? [])].reverse().find((m) => m.role === "assistant")
    lastRun = last?.stopReason === "error" ? "error" : last?.stopReason === "aborted" ? "cancelled" : "ok"
  })

  function settle(ctx: Ctx) {
    // The completion wake starts a new run, which settles again. ponytail: a
    // task that dies without ever waking the parent holds the pane busy until
    // the next run; publish task state from the host if that bites.
    if (BG_FILTER_ENABLED && lastRun === "ok" && (wakeSources.size > 0 || waitingOnBackgroundTasks(ctx))) {
      heldCtx = ctx
      return
    }
    setPaneOption("@oc-status", "idle")
    cancelPending()
    pendingComplete = setTimeout(() => {
      pendingComplete = undefined
      if (!ctx.isIdle()) return
      if (lastRun === "ok") dispatch("complete", `Session has finished${suffix()}`)
      else dispatch("error", `Session ${lastRun === "cancelled" ? "was cancelled" : "encountered an error"}${suffix()}`)
    }, IDLE_DELAY_MS)
  }

  pi.on("agent_settled", (_event, ctx) => settle(ctx))

  pi.events.on("wake_source_state", (payload) => {
    const { source, activeCount } = payload ?? {}
    if (!source || source === "ask-user" || typeof activeCount !== "number") return
    if (activeCount > 0) wakeSources.set(source, activeCount)
    else wakeSources.delete(source)
    // Last source drained: normally its wake starts a run (agent_start cancels
    // the debounce); if nothing wakes the session, settle as usual.
    if (wakeSources.size === 0 && heldCtx) {
      const ctx = heldCtx
      heldCtx = undefined
      settle(ctx)
    }
  })

  // One active/inactive pair per built-in question or host dialog.
  pi.events.on("herdr:blocked", (payload) => {
    if (payload?.active) dispatch("question", `Session has a question${suffix()}`)
  })

  pi.on("session_shutdown", () => {
    cancelPending()
    setPaneOption("@oc-status", "idle")
  })
}
