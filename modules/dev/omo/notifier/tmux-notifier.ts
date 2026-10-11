// Publishes this omo session's state as options on the tmux pane it runs in.
// Pane options die with the pane, so there is no queue to keep in sync:
//   @agent-sid      session id: tmux-resurrect (cli/tmux), the agent CLI
//   @agent-status   busy | idle: status bar colour, session picker, wts, widget
//   @agent-attn     complete | error | question: this pane needs you. Cleared
//                   when you look at its window or jump to it with prefix+N
//                   (tmux-agent-notify.sh), or when the session runs again.
//   @agent-attn-at  epoch seconds, so prefix+N jumps to the newest first
// A clean exit unsets them all; readers also skip panes no longer running
// omo, which covers a crash.
import { spawn, spawnSync } from "node:child_process"

type EventKind = "complete" | "error" | "question"

// The slice of senpi's ExtensionAPI this file touches.
export type Ctx = {
  cwd: string
  isIdle(): boolean
  sessionManager: { getSessionId(): string }
}
export type RunMessage = { role?: string; stopReason?: string }
export type Pi = {
  sessionKind: "interactive" | "worker"
  on(event: "session_start" | "agent_start" | "agent_settled" | "session_shutdown", handler: (event: unknown, ctx: Ctx) => void): void
  on(event: "agent_end", handler: (event: { messages?: RunMessage[] }, ctx: Ctx) => void): void
  events: {
    on(channel: "herdr:blocked", handler: (payload: { active?: boolean; label?: string }) => void): void
    on(channel: "wake_source_state", handler: (payload: { source?: string; activeCount?: number }) => void): void
  }
}

const TMUX_PANE = process.env.TMUX_PANE ?? ""
// Substituted by notifier.nix. It used to come from an env var, which only
// reached omo when it was started from a login shell: panes started by tmux
// or the agent CLI played the macOS fallback sound instead.
const SOUND_DIR = "@soundDir@"

function runDetached(cmd: string, args: string[]) {
  try {
    const proc = spawn(cmd, args, { stdio: "ignore", detached: true })
    proc.on("error", () => {})
    proc.unref()
  } catch {
    // Notifier side-effects must never break the omo session.
  }
}

// Synchronous, so writes land in order: an 'idle' arriving after a 'busy'
// would park the pane on the wrong state. Pass several commands separated by
// ";" to send them in one call.
function tmux(...args: string[]): boolean {
  try {
    const res = spawnSync("tmux", args, { stdio: "ignore", timeout: 300 })
    return !res.error && res.status === 0
  } catch {
    return false
  }
}

const set = (option: string, value: string) => ["set-option", "-p", "-t", TMUX_PANE, option, value]
const unset = (option: string) => ["set-option", "-pu", "-t", TMUX_PANE, option]
const seq = (...cmds: string[][]) => tmux(...cmds.flatMap((c, i) => (i ? [";", ...c] : c)))

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

// idleDelayMs: how long the session must stay idle before it counts as done.
// omo passes only `pi`; the check passes 0.
export default function (pi: Pi, idleDelayMs = 1500) {
  // Worker sessions (subagents) run in the shared RPC host, whose TMUX_PANE
  // belongs to whichever pane happened to start it.
  if (pi.sessionKind !== "interactive" || !TMUX_PANE) return

  let sessionID = ""
  let lastRun: "ok" | "error" | "cancelled" = "ok"
  let pendingComplete: ReturnType<typeof setTimeout> | undefined
  // Things that will wake this session on their own, as omo publishes them on
  // its event bus: background tasks (senpi-task), monitors, background bash
  // sessions, detached eval cells, DAG runs. A pending ask-user question is
  // the user's move, so it does not hold the pane busy.
  const wakeSources = new Map<string, number>()
  let heldCtx: Ctx | undefined

  function dispatch(event: EventKind) {
    if (isPaneFocusedInAttachedClient()) return
    seq(set("@agent-attn", event), set("@agent-attn-at", String(Math.floor(Date.now() / 1000))))
    runDetached("afplay", ["-v", "0.7", `${SOUND_DIR}/${event}.wav`])
  }

  function bind(ctx: Ctx) {
    const id = ctx.sessionManager.getSessionId()
    // Latch only once the claim lands, so a dropped write retries next event.
    if (id && id !== sessionID && seq(set("@agent-sid", id))) sessionID = id
  }

  function cancelPending() {
    clearTimeout(pendingComplete)
    pendingComplete = undefined
  }

  pi.on("session_start", (_event, ctx) => {
    cancelPending()
    bind(ctx)
    seq(set("@agent-status", "idle"))
  })

  pi.on("agent_start", (_event, ctx) => {
    cancelPending()
    heldCtx = undefined
    bind(ctx)
    // Running again: whatever it was waiting on you for is no longer true.
    seq(set("@agent-status", "busy"), unset("@agent-attn"), unset("@agent-attn-at"))
  })

  pi.on("agent_end", (event) => {
    const last = [...(event.messages ?? [])].reverse().find((m) => m.role === "assistant")
    lastRun = last?.stopReason === "error" ? "error" : last?.stopReason === "aborted" ? "cancelled" : "ok"
  })

  function settle(ctx: Ctx) {
    // The wake starts a new run, which settles again.
    if (lastRun === "ok" && wakeSources.size > 0) {
      heldCtx = ctx
      return
    }
    seq(set("@agent-status", "idle"))
    cancelPending()
    pendingComplete = setTimeout(() => {
      pendingComplete = undefined
      // A reload inside idleDelayMs leaves ctx on the old extension
      // generation, where isIdle() throws; uncaught in a timer, that kills omo.
      try {
        if (!ctx.isIdle()) return
      } catch {
        return
      }
      dispatch(lastRun === "ok" ? "complete" : "error")
    }, idleDelayMs)
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
    if (payload?.active) dispatch("question")
  })

  pi.on("session_shutdown", () => {
    cancelPending()
    sessionID = ""
    seq(unset("@agent-sid"), unset("@agent-status"), unset("@agent-attn"), unset("@agent-attn-at"))
  })
}
