// Switchable primary agents, opencode-style. `/agent [name]` (or Tab on an
// empty prompt / ctrl+x a, which cycle via `agents:cycle`) moves this
// session between plain OmO and the orchestrator; the choice is saved in
// the session so a resume keeps it. `omo --agent orchestrator` starts in it.
// omo.nix installs this directory as ~/.omo/agent/extensions/agents; to try
// an edit before rebuilding:
// omo -e ~/nix-config/modules/dev/omo/agents/index.ts
import { readFileSync } from "node:fs"
import type { ExtensionAPI } from "@code-yeongyu/senpi"

const AGENTS = ["omo", "orchestrator"] as const
type Agent = (typeof AGENTS)[number]
const ENTRY = "agents-active"
const ORCHESTRATOR = readFileSync(new URL("./orchestrator.md", import.meta.url), "utf8")
// The `agent` CLI starts every message it relays with this marker (see
// ../agent/agent.ts); without the note, a steer arriving mid-task reads like
// an injected instruction and gets ignored.
const RELAYED =
  "A user message that starts with `[orchestrator]` was sent by the user's orchestrator session on the user's behalf. Treat it as the user's own message."

// A `## <title>` section of orchestrator.md, heading included.
function section(title: string): string {
  const start = ORCHESTRATOR.indexOf(`## ${title}\n`)
  if (start < 0) throw new Error(`orchestrator.md has no "## ${title}" section`)
  const end = ORCHESTRATOR.indexOf("\n## ", start + 1)
  return ORCHESTRATOR.slice(start, end < 0 ? undefined : end).trim()
}

type Entry = { type: string; customType?: string; data?: { agent?: string } }
const isAgent = (name: unknown): name is Agent => AGENTS.includes(name as Agent)

export default function (pi: ExtensionAPI) {
  let active: Agent = "omo"

  function use(agent: Agent) {
    active = agent
    pi.events.emit("agents:active", agent)
  }

  // Switches and saves the choice in the session, so a resume keeps it.
  function switchTo(agent: Agent) {
    use(agent)
    pi.appendEntry(ENTRY, { agent })
  }
  const next = () => AGENTS[(AGENTS.indexOf(active) + 1) % AGENTS.length]

  // The prompt's Tab (empty draft) and ctrl+x a.
  pi.events.on("agents:cycle", () => switchTo(next()))

  pi.registerFlag("agent", { description: `Primary agent to start with (${AGENTS.join(", ")})`, type: "string" })

  pi.on("session_start", (_e, ctx) => {
    const saved = (ctx.sessionManager.getEntries() as Entry[]).filter((e) => e.type === "custom" && e.customType === ENTRY).pop()
    const flag = pi.getFlag("agent")
    use(isAgent(saved?.data?.agent) ? saved.data.agent : isAgent(flag) ? flag : "omo")
  })

  pi.registerCommand("agent", {
    description: `Switch primary agent (${AGENTS.join(", ")}); no argument cycles`,
    getArgumentCompletions: (prefix: string) => {
      const items = AGENTS.filter((a) => a.startsWith(prefix)).map((a) => ({ value: a, label: a }))
      return items.length > 0 ? items : null
    },
    handler: async (args, ctx) => {
      const name = args?.trim()
      const agent = name ? name : next()
      if (!isAgent(agent)) {
        ctx.ui.notify(`Unknown agent "${name}". Available: ${AGENTS.join(", ")}`, "error")
        return
      }
      switchTo(agent)
      ctx.ui.notify(`Agent: ${agent}`, "info")
    },
  })

  // One-shot handoff from a plain session: spawn agents for work found
  // mid-research, briefed from this conversation, without switching modes.
  // Sent as a real user message: a system-prompt switch alone gets outweighed
  // by the transcript. Plain agents learn about the `agent` CLI only here.
  pi.registerCommand("orchestrate", {
    description: "Hand work to new agents (worktrees + PRs), briefed from this conversation",
    handler: async (args, ctx) => {
      const task = args?.trim() || "the issue we just found"
      const message = `Hand this off to agents instead of doing it here: ${task}

Split it as "Independent and dependent work" below describes and spawn the agents yourself, each briefed from what this conversation established (default: open a PR). Tell me their names and how to reach them. Don't make the change here or check on the agents afterwards; then continue what we were doing.

${section("The `agent` CLI")}

${section("Independent and dependent work")}

${section("Briefs")}`
      if (ctx.isIdle()) pi.sendUserMessage(message)
      else pi.sendUserMessage(message, { deliverAs: "steer" })
    },
  })

  pi.on("before_agent_start", (event: { systemPrompt: string }) => ({
    systemPrompt: `${event.systemPrompt}\n\n${active === "orchestrator" ? ORCHESTRATOR : RELAYED}`,
  }))
}
