// Switchable primary agents, opencode-style. `/agent [name]` (or ctrl+x a in
// the prompt, which cycles) moves this session between plain OmO and the
// orchestrator; the choice is saved in the session so a resume keeps it.
// `omo --agent orchestrator` starts in it. omo.nix installs this directory
// as ~/.omo/agent/extensions/agents; to try an edit before rebuilding:
// omo -e ~/nix-config/modules/dev/omo/agents/index.ts
import { readFileSync } from "node:fs"
import type { ExtensionAPI } from "@code-yeongyu/senpi"
import tools from "./tools.ts"

const AGENTS = ["omo", "orchestrator"] as const
type Agent = (typeof AGENTS)[number]
const ENTRY = "agents-active"
const ORCHESTRATOR = readFileSync(new URL("./orchestrator.md", import.meta.url), "utf8")

type Entry = { type: string; customType?: string; data?: { agent?: string } }
const isAgent = (name: unknown): name is Agent => AGENTS.includes(name as Agent)

export default function (pi: ExtensionAPI) {
  let active: Agent = "omo"
  const orchestratorTools = tools(pi)

  // The orchestrator's tools exist in every session but are only active in
  // its own, so agents it spawns can't spawn agents.
  function use(agent: Agent) {
    active = agent
    const rest = pi.getActiveTools().filter((t) => !orchestratorTools.includes(t))
    pi.setActiveTools(agent === "orchestrator" ? [...rest, ...orchestratorTools] : rest)
    pi.events.emit("agents:active", agent)
  }

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
      const next = name ? name : AGENTS[(AGENTS.indexOf(active) + 1) % AGENTS.length]
      if (!isAgent(next)) {
        ctx.ui.notify(`Unknown agent "${name}". Available: ${AGENTS.join(", ")}`, "error")
        return
      }
      use(next)
      pi.appendEntry(ENTRY, { agent: next })
      ctx.ui.notify(`Agent: ${next}`, "info")
    },
  })

  pi.on("before_agent_start", (event: { systemPrompt: string }) =>
    active === "orchestrator" ? { systemPrompt: `${event.systemPrompt}\n\n${ORCHESTRATOR}` } : undefined,
  )
}
