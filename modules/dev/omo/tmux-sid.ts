// Publish this pane's omo session id as @oc-sid, so tmux-resurrect resumes
// each agent pane into its own session (cli/tmux/resurrect-agents.sh) instead
// of `--continue`, which brings every pane in a project back as the newest
// one. tmux-notifier.ts publishes it too, but ships only with opencode-manager.
import { spawnSync } from "node:child_process"

type Ctx = { sessionManager: { getSessionId(): string } }
type Pi = {
  sessionKind: "interactive" | "worker"
  on(event: "session_start" | "agent_start", handler: (event: unknown, ctx: Ctx) => void): void
}

export default function (pi: Pi) {
  const pane = process.env.TMUX_PANE
  // Workers run in the shared RPC host, whose TMUX_PANE is not theirs.
  if (pi.sessionKind !== "interactive" || !pane) return
  let published = ""
  // session_start covers /new, /resume and /fork; agent_start retries a
  // write that failed.
  const publish = (_event: unknown, ctx: Ctx) => {
    const id = ctx.sessionManager.getSessionId()
    if (!id || id === published) return
    const res = spawnSync("tmux", ["set-option", "-p", "-t", pane, "@oc-sid", id], { stdio: "ignore", timeout: 300 })
    if (!res.error && res.status === 0) published = id
  }
  pi.on("session_start", publish)
  pi.on("agent_start", publish)
}
