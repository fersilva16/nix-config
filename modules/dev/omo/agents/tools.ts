// The orchestrator's hands: start an omo in a fresh `wt` worktree and tmux
// session, then list, read and steer those sessions. Everything is plain tmux,
// so the user can switch into any agent's session and take over.
import { mkdirSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import type { ExtensionAPI } from "@code-yeongyu/senpi"
import { Type } from "typebox"

type Exec = { stdout: string; stderr: string; code: number }
const NAME = /^[a-z0-9][a-z0-9._-]*$/
const MAX_LINES = 200

export default function tools(pi: ExtensionAPI): string[] {
  async function run(cmd: string, args: string[], what: string): Promise<string> {
    const r = (await pi.exec(cmd, args)) as Exec
    if (r.code !== 0) throw new Error(`${what}: ${(r.stderr || r.stdout).trim() || `exit ${r.code}`}`)
    return r.stdout.trim()
  }

  // wt names sessions "<root session>/<name>", from whichever session it runs in.
  async function project(): Promise<string> {
    if (!process.env.TMUX) throw new Error("the orchestrator needs to run inside tmux")
    return (await run("tmux", ["display-message", "-p", "#{session_name}"], "tmux")).split("/")[0]
  }

  async function sessionOf(name: string): Promise<string> {
    if (!NAME.test(name)) throw new Error(`invalid agent name "${name}": use lowercase kebab-case`)
    return `${await project()}/${name}`
  }

  // The pane omo announced itself in (tmux-notifier sets @oc-sid), else the
  // session's first pane.
  async function paneOf(session: string): Promise<string> {
    const rows = (await run("tmux", ["list-panes", "-s", "-t", `=${session}`, "-F", "#{pane_id}\t#{@oc-sid}"], `no agent session ${session}`))
      .split("\n")
      .map((l) => l.split("\t"))
    return (rows.find(([, sid]) => sid) ?? rows[0])[0]
  }

  function scratch(session: string, text: string): string {
    const dir = join(process.env.TMPDIR ?? tmpdir(), "omo-orchestrator")
    mkdirSync(dir, { recursive: true })
    const file = join(dir, `${session.replaceAll("/", "__")}-${Date.now()}.md`)
    writeFileSync(file, text)
    return file
  }

  const text = (t: string) => ({ content: [{ type: "text" as const, text: t }], details: {} })

  pi.registerTool({
    name: "agent_spawn",
    label: "Spawn agent",
    description:
      "Start a new omo agent in its own git worktree (created with `wt`, branch named after it) and tmux session `<project>/<name>`, with `prompt` as its first message. The user can switch to that session to watch or take over.",
    promptSnippet: "Start an omo agent in a new worktree + tmux session",
    parameters: Type.Object({
      name: Type.String({ description: "Short kebab-case name: worktree, branch suffix and tmux session" }),
      prompt: Type.String({ description: "Self-contained task for the agent; it sees nothing of this conversation" }),
    }),
    async execute(_id, params: { name: string; prompt: string }) {
      const session = await sessionOf(params.name)
      const exists = (await pi.exec("tmux", ["has-session", "-t", `=${session}`])) as Exec
      if (exists.code === 0) throw new Error(`${session} already exists; use agent_send to talk to it`)
      // WT_SYNC: the worktree is checked out before wt returns. WT_DETACH:
      // leave the user where they are instead of switching them into it.
      await run(
        "fish",
        ["-c", "set -x WT_SYNC 1; set -x WT_DETACH 1; wt $argv[1]", params.name],
        "wt",
      )
      const pane = await paneOf(session)
      const file = scratch(session, params.prompt)
      // Typed into the session's own fish so the agent gets the same login
      // + direnv environment as any pane you open; the leading space keeps it
      // out of fish history. "$(…)" keeps the prompt's newlines.
      await run("tmux", ["send-keys", "-t", pane, "-l", ` omo "$(cat '${file}')"`], "tmux send-keys")
      await run("tmux", ["send-keys", "-t", pane, "Enter"], "tmux send-keys")
      const path = await run("tmux", ["display-message", "-p", "-t", pane, "#{pane_current_path}"], "tmux")
      return text(`Started ${params.name}: tmux session ${session}, worktree ${path}`)
    },
  })

  pi.registerTool({
    name: "agent_list",
    label: "List agents",
    description:
      "List this project's worktree sessions (`<project>/<name>`) with the running command and omo status (@oc-status: busy, idle, question, permission, error).",
    promptSnippet: "List this project's agent sessions and their status",
    parameters: Type.Object({}),
    async execute() {
      const root = await project()
      const sessions = (await run("tmux", ["list-sessions", "-F", "#{session_name}"], "tmux"))
        .split("\n")
        .filter((s) => s.startsWith(`${root}/`))
      if (sessions.length === 0) return text(`No agent sessions under ${root}/`)
      const rows = await Promise.all(
        sessions.map(async (s) => {
          const pane = await paneOf(s)
          const info = await run("tmux", ["display-message", "-p", "-t", pane, "#{pane_current_command}\t#{@oc-status}"], "tmux")
          const [cmd, status] = info.split("\t")
          return `${s.slice(root.length + 1)}\t${cmd}\t${status || "-"}`
        }),
      )
      return text(`name\tcommand\tstatus\n${rows.join("\n")}`)
    },
  })

  pi.registerTool({
    name: "agent_peek",
    label: "Peek agent",
    description: "Read the last lines of an agent's screen (its tmux pane).",
    promptSnippet: "Read an agent's recent screen",
    parameters: Type.Object({
      name: Type.String({ description: "Agent name as given to agent_spawn" }),
      lines: Type.Optional(Type.Number({ description: `Lines of history, default 60, max ${MAX_LINES}` })),
    }),
    async execute(_id, params: { name: string; lines?: number }) {
      const pane = await paneOf(await sessionOf(params.name))
      const n = Math.min(Math.max(1, Math.floor(params.lines ?? 60)), MAX_LINES)
      const screen = await run("tmux", ["capture-pane", "-p", "-J", "-t", pane, "-S", `-${n}`], "tmux capture-pane")
      return text(screen.split("\n").slice(-n).join("\n") || "(empty screen)")
    },
  })

  pi.registerTool({
    name: "agent_send",
    label: "Send to agent",
    description:
      "Type a message into an agent's prompt and press Enter. While the agent works this steers it; when it is idle this starts its next turn.",
    promptSnippet: "Send a message to an agent's prompt",
    parameters: Type.Object({
      name: Type.String({ description: "Agent name as given to agent_spawn" }),
      message: Type.String(),
    }),
    async execute(_id, params: { name: string; message: string }) {
      const session = await sessionOf(params.name)
      const pane = await paneOf(session)
      // A bracketed paste, so newlines in the message don't submit early.
      const buffer = `omo-orchestrator-${Date.now()}`
      await run("tmux", ["load-buffer", "-b", buffer, scratch(session, params.message)], "tmux load-buffer")
      await run("tmux", ["paste-buffer", "-p", "-d", "-b", buffer, "-t", pane], "tmux paste-buffer")
      await run("tmux", ["send-keys", "-t", pane, "Enter"], "tmux send-keys")
      return text(`Sent to ${session}`)
    },
  })

  return ["agent_spawn", "agent_list", "agent_peek", "agent_send"]
}
