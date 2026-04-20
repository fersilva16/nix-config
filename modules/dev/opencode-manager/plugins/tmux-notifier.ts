// Routes opencode session events to tmux-opencode-manager using the
// real sessionID, bypassing @mohak34/opencode-notifier's command hook
// (which spawns server-side without TMUX_PANE and mis-tags
// notifications to whichever tmux client is currently attached).
// mohak34 still owns sound + desktop notifications; its `command` is
// disabled in the notifier config. Auto-discovered from
// ~/.config/opencode/plugin/*.ts by opencode's ConfigPlugin.load.

import { spawn } from "child_process"
import { basename } from "path"

const CMD = "tmux-opencode-manager"

const TMUX_PANE = process.env.TMUX_PANE ?? ""

// Mirrors @mohak34/opencode-notifier's IDLE_COMPLETE_DELAY_MS. Avoids
// firing "complete" on transient idles inside a single turn (e.g.,
// between tool calls).
const IDLE_DELAY_MS = 350

type Client = {
  session: {
    get: (args: { path: { id: string } }) => Promise<{ data?: { title?: string; parentID?: string | null } }>
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

function fireNotify(event: string, sessionID: string | null, message: string) {
  const args = ["notify", "add", "--event", event, "--require-target"]
  if (sessionID) args.push("--session-id", sessionID)
  if (TMUX_PANE) args.push("--pane-id", TMUX_PANE)
  args.push(message)

  try {
    const proc = spawn(CMD, args, { stdio: "ignore", detached: true })
    proc.on("error", () => {})
    proc.unref()
  } catch {
    // Notifier must never break the opencode session.
  }
}

function setPaneOption(option: string, value: string) {
  if (!TMUX_PANE) return
  try {
    const proc = spawn("tmux", ["set-option", "-p", "-t", TMUX_PANE, option, value], {
      stdio: "ignore",
      detached: true,
    })
    proc.on("error", () => {})
    proc.unref()
  } catch {
    // Pane option setup is best-effort; widget visibility is non-critical.
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

  async function emitComplete(sessionID: string) {
    const { title, isChild } = await getSessionInfo(client, sessionID)
    if (isChild) return
    fireNotify("complete", sessionID, `Session has finished${buildSuffix(title)}`)
  }

  async function emitError(sessionID: string | null, cancelled: boolean) {
    const { title } = await getSessionInfo(client, sessionID)
    const verb = cancelled ? "was cancelled" : "encountered an error"
    fireNotify("error", sessionID, `Session ${verb}${buildSuffix(title)}`)
  }

  async function emitPermission(sessionID: string | null) {
    const { title } = await getSessionInfo(client, sessionID)
    fireNotify("permission", sessionID, `Session needs permission${buildSuffix(title)}`)
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
      fireNotify("permission", null, "Session needs permission")
    },

    "tool.execute.before": async ({ tool }) => {
      if (tool === "question") fireNotify("question", null, "Session has a question")
    },
  }
}

export default TmuxNotifierPlugin
