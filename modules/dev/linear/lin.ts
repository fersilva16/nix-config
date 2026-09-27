// omo `/lin`: the opencode command (`!`fish -c lin``) sends the current
// branch's Linear issue as the prompt. omo prompt templates have no shell
// interpolation, so a command handler does the same.
import { spawnSync } from "node:child_process"

type Ctx = { ui: { notify(message: string, level: "info" | "warning" | "error"): void } }
type Pi = {
  registerCommand(name: string, spec: { description: string; handler: (args: string, ctx: Ctx) => void }): void
  sendUserMessage(content: string): void
}

export default function (pi: Pi) {
  pi.registerCommand("lin", {
    description: "Load Linear issue context",
    handler: (_args, ctx) => {
      const res = spawnSync("fish", ["-c", "lin"], { encoding: "utf8", timeout: 30_000 })
      const out = (res.stdout ?? "").trim()
      if (res.status !== 0 || !out) {
        ctx.ui.notify(`lin: ${(res.stderr ?? "").trim() || "no Linear issue for this branch"}`, "warning")
        return
      }
      pi.sendUserMessage(out)
    },
  })
}
