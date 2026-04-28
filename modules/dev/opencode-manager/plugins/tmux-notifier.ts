// Full-stack opencode notifier: tmux widget + sound + desktop.
// Replaces @mohak34/opencode-notifier so we can filter synthetic turns
// from oh-my-openagent (which would otherwise trigger on every
// TODO CONTINUATION / BACKGROUND TASK COMPLETE etc.).
//
// Env (all optional):
//   OPENCODE_TMUX_NOTIFIER_SOUND=0       disable sound
//   OPENCODE_TMUX_NOTIFIER_DESKTOP=0     disable desktop notifications
//   OPENCODE_TMUX_NOTIFIER_OMO_FILTER=0  allow OMO turns to notify
//   OPENCODE_TMUX_NOTIFIER_BG_FILTER=0   allow notifications when waiting on
//                                        spawned background task() agents
//   OPENCODE_TMUX_NOTIFIER_IDLE_DELAY_MS=1500
//                                        debounce window before firing on idle.
//                                        Larger values give OMO directives
//                                        (TODO CONTINUATION etc.) time to land
//                                        and cancel the pending notification.
//   OPENCODE_TMUX_NOTIFIER_VOLUME=0.5    sound volume 0-1 (default 0.7)

import { spawn, spawnSync } from "child_process"
import { existsSync } from "fs"
import { basename } from "path"
import { platform } from "os"

const CMD = "tmux-opencode-manager"
const TMUX_PANE = process.env.TMUX_PANE ?? ""
const PLATFORM = platform()

const IDLE_DELAY_MS = (() => {
  const raw = process.env.OPENCODE_TMUX_NOTIFIER_IDLE_DELAY_MS
  const n = raw ? Number(raw) : NaN
  if (Number.isFinite(n) && n >= 0) return n
  return 1500
})()

const OMO_INTERNAL_INITIATOR_MARKER = "<!-- OMO_INTERNAL_INITIATOR -->"

const SOUND_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_SOUND !== "0"
const DESKTOP_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_DESKTOP !== "0"
const OMO_FILTER_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_OMO_FILTER !== "0"
const BG_FILTER_ENABLED = process.env.OPENCODE_TMUX_NOTIFIER_BG_FILTER !== "0"

const VOLUME = (() => {
  const raw = process.env.OPENCODE_TMUX_NOTIFIER_VOLUME
  const n = raw ? Number(raw) : NaN
  if (Number.isFinite(n) && n >= 0 && n <= 1) return n
  return 0.7
})()

const CUSTOM_SOUND_DIR = process.env.OPENCODE_TMUX_NOTIFIER_SOUND_DIR ?? ""

const MAC_SOUNDS: Record<EventKind, string> = {
  complete: "/System/Library/Sounds/Glass.aiff",
  permission: "/System/Library/Sounds/Ping.aiff",
  error: "/System/Library/Sounds/Basso.aiff",
  question: "/System/Library/Sounds/Tink.aiff",
}

function resolveSoundPath(event: EventKind): string {
  if (CUSTOM_SOUND_DIR) {
    const custom = `${CUSTOM_SOUND_DIR}/${event}.wav`
    if (existsSync(custom)) return custom
  }
  return MAC_SOUNDS[event]
}

type EventKind = "complete" | "permission" | "error" | "question"

type ToolState = {
  status?: string
  input?: Record<string, unknown>
}
type MessagePart = {
  type?: string
  text?: string
  tool?: string
  state?: ToolState
}
type MessageInfo = { id?: string; role?: string; time?: { created?: number } }
type MessageEntry = { info?: MessageInfo; parts?: MessagePart[] }

type Client = {
  session: {
    get: (args: { path: { id: string } }) => Promise<{ data?: { title?: string; parentID?: string | null } }>
    messages?: (args: { path: { id: string } }) => Promise<{ data?: MessageEntry[] }>
  }
}

type PluginInput = {
  client: Client
  directory?: string
}

type EventInput = {
  event: {
    type: string
    properties: Record<string, any>
  }
}

type Hooks = {
  event?: (input: EventInput) => Promise<void> | void
  "permission.ask"?: () => Promise<void> | void
  "tool.execute.before"?: (input: { tool: string }) => Promise<void> | void
}

function runDetached(cmd: string, args: string[]) {
  try {
    const proc = spawn(cmd, args, { stdio: "ignore", detached: true })
    proc.on("error", () => {})
    proc.unref()
  } catch {
    // Notifier side-effects must never break the opencode session.
  }
}

function fireTmuxNotify(event: EventKind, sessionID: string | null, message: string) {
  const args = ["notify", "add", "--event", event, "--require-target"]
  if (sessionID) args.push("--session-id", sessionID)
  if (TMUX_PANE) args.push("--pane-id", TMUX_PANE)
  args.push(message)
  runDetached(CMD, args)
}

function playSound(event: EventKind) {
  if (!SOUND_ENABLED) return
  const path = resolveSoundPath(event)
  if (!path) return
  if (PLATFORM === "darwin") {
    runDetached("afplay", ["-v", String(VOLUME), path])
  } else if (PLATFORM === "linux") {
    runDetached("paplay", [path])
  }
}

function sendDesktopNotification(title: string, body: string) {
  if (!DESKTOP_ENABLED) return
  if (PLATFORM === "darwin") {
    const escaped = (s: string) => s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    runDetached("osascript", ["-e", `display notification "${escaped(body)}" with title "${escaped(title)}"`])
  } else if (PLATFORM === "linux") {
    runDetached("notify-send", ["--app-name=opencode", title, body])
  }
}

function setPaneOption(option: string, value: string) {
  if (!TMUX_PANE) return
  runDetached("tmux", ["set-option", "-p", "-t", TMUX_PANE, option, value])
}

function isPaneFocusedInAttachedClient(): boolean {
  if (!TMUX_PANE) return false
  try {
    const res = spawnSync(
      "tmux",
      ["display-message", "-p", "-t", TMUX_PANE, "#{window_active} #{session_attached}"],
      { encoding: "utf8", timeout: 300 },
    )
    if (res.status !== 0 || !res.stdout) return false
    const [active, attached] = res.stdout.trim().split(/\s+/)
    return active === "1" && Number(attached) > 0
  } catch {
    return false
  }
}

async function getSessionInfo(
  client: Client,
  sessionID: string | null,
): Promise<{ title: string; isChild: boolean }> {
  if (!sessionID) return { title: "", isChild: false }
  try {
    const { data } = await client.session.get({ path: { id: sessionID } })
    const raw = data?.title ?? ""
    const title = !raw || raw.startsWith("<") || raw.startsWith("{") ? "" : raw
    const isChild = typeof data?.parentID === "string" && data.parentID.length > 0
    return { title, isChild }
  } catch {
    return { title: "", isChild: false }
  }
}

async function isLastUserMessageFromOmo(client: Client, sessionID: string): Promise<boolean> {
  if (!OMO_FILTER_ENABLED) return false
  if (typeof client.session.messages !== "function") return false
  try {
    const { data } = await client.session.messages({ path: { id: sessionID } })
    if (!Array.isArray(data)) return false

    let latest: MessageEntry | null = null
    let latestTime = Number.NEGATIVE_INFINITY
    for (const entry of data) {
      if (entry?.info?.role !== "user") continue
      const t = entry.info?.time?.created ?? Number.NEGATIVE_INFINITY
      if (t > latestTime) {
        latestTime = t
        latest = entry
      }
    }

    if (!latest || !Array.isArray(latest.parts)) return false
    return latest.parts.some(
      (p) => p?.type === "text" && typeof p.text === "string" && p.text.includes(OMO_INTERNAL_INITIATOR_MARKER),
    )
  } catch {
    return false
  }
}

function isPendingBackgroundTaskPart(part: MessagePart): boolean {
  if (part?.type !== "tool" || part.tool !== "task") return false
  if (part.state?.status !== "completed") return false
  return part.state?.input?.run_in_background === true
}

async function isWaitingOnBackgroundTasks(client: Client, sessionID: string): Promise<boolean> {
  if (!BG_FILTER_ENABLED) return false
  if (typeof client.session.messages !== "function") return false
  try {
    const { data } = await client.session.messages({ path: { id: sessionID } })
    if (!Array.isArray(data)) return false

    let latest: MessageEntry | null = null
    let latestTime = Number.NEGATIVE_INFINITY
    for (const entry of data) {
      if (entry?.info?.role !== "assistant") continue
      const t = entry.info?.time?.created ?? Number.NEGATIVE_INFINITY
      if (t > latestTime) {
        latestTime = t
        latest = entry
      }
    }

    if (!latest || !Array.isArray(latest.parts)) return false
    return latest.parts.some(isPendingBackgroundTaskPart)
  } catch {
    return false
  }
}

export const TmuxNotifierPlugin = async ({ client, directory }: PluginInput): Promise<Hooks> => {
  const projectName = directory ? basename(directory) : null
  const pendingIdle = new Map<string, ReturnType<typeof setTimeout>>()

  let currentSessionID: string | null = null

  function bindSessionToPane(sessionID: string) {
    if (!TMUX_PANE || sessionID === currentSessionID) return
    currentSessionID = sessionID
    setPaneOption("@oc-sid", sessionID)
    setPaneOption("@oc-status", "active")
    if (directory) setPaneOption("@oc-dir", directory)
  }

  function clearPending(sessionID: string) {
    const t = pendingIdle.get(sessionID)
    if (t) {
      clearTimeout(t)
      pendingIdle.delete(sessionID)
    }
  }

  function buildSuffix(title: string): string {
    if (title) return `: ${title}`
    if (projectName) return ` (${projectName})`
    return ""
  }

  function dispatchAll(event: EventKind, sessionID: string | null, titleForDesktop: string, body: string) {
    if (isPaneFocusedInAttachedClient()) return
    fireTmuxNotify(event, sessionID, body)
    playSound(event)
    sendDesktopNotification(titleForDesktop, body)
  }

  async function emitComplete(sessionID: string) {
    const { title, isChild } = await getSessionInfo(client, sessionID)
    if (isChild) return
    if (await isLastUserMessageFromOmo(client, sessionID)) return
    if (await isWaitingOnBackgroundTasks(client, sessionID)) return
    const body = `Session has finished${buildSuffix(title)}`
    dispatchAll("complete", sessionID, projectName ?? "opencode", body)
  }

  async function emitError(sessionID: string | null, cancelled: boolean) {
    const { title } = await getSessionInfo(client, sessionID)
    const verb = cancelled ? "was cancelled" : "encountered an error"
    const body = `Session ${verb}${buildSuffix(title)}`
    dispatchAll("error", sessionID, projectName ?? "opencode", body)
  }

  async function emitPermission(sessionID: string | null) {
    const { title } = await getSessionInfo(client, sessionID)
    const body = `Session needs permission${buildSuffix(title)}`
    dispatchAll("permission", sessionID, projectName ?? "opencode", body)
  }

  return {
    event: async ({ event }) => {
      const props = event.properties ?? {}
      const sessionID: string | null =
        typeof props.sessionID === "string" && props.sessionID.length > 0
          ? props.sessionID
          : typeof props.info?.id === "string"
            ? props.info.id
            : null

      if (event.type === "session.created" && sessionID) {
        bindSessionToPane(sessionID)
        return
      }

      if (event.type === "session.status") {
        if (sessionID) bindSessionToPane(sessionID)
        if (props.status?.type === "busy" && sessionID) clearPending(sessionID)
        return
      }

      if (event.type === "session.idle" && sessionID) {
        bindSessionToPane(sessionID)
        clearPending(sessionID)
        const timer = setTimeout(() => {
          pendingIdle.delete(sessionID)
          void emitComplete(sessionID)
        }, IDLE_DELAY_MS)
        pendingIdle.set(sessionID, timer)
        return
      }

      if (event.type === "session.error") {
        if (sessionID) clearPending(sessionID)
        await emitError(sessionID, props.error?.name === "MessageAbortedError")
        return
      }

      if (event.type === "permission.asked") {
        await emitPermission(sessionID)
        return
      }
    },

    "permission.ask": async () => {
      const body = "Session needs permission"
      dispatchAll("permission", null, projectName ?? "opencode", body)
    },

    "tool.execute.before": async ({ tool }) => {
      if (tool === "question") {
        const body = "Session has a question"
        dispatchAll("question", null, projectName ?? "opencode", body)
      }
    },
  }
}

export default TmuxNotifierPlugin
