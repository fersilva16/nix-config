// /continue: resume after a cancelled or errored turn, or say yes to the
// agent's own "want me to ...?", without typing a message. Extensions can't
// call the agent's continue(), and it refuses to resume from an assistant
// message (where both cases end) unless something is queued. So this queues
// a hidden custom message: nothing shows in the transcript, and the model gets
// the nudge as a user turn. Arguments are appended as extra steering:
// `/continue but skip the tests`. /y is the short alias.
import type { ExtensionAPI, ExtensionCommandContext } from "@code-yeongyu/senpi"

const COMMAND = "continue"
const ALIAS = "y"

const NUDGE = [
  "Continue from where you stopped.",
  "If you ended by proposing something or asking whether to go ahead, the answer is yes: do it.",
  "If your last turn was cancelled or errored mid-step, first check the real state of what you were doing and resume from there. Do not blindly re-run a side-effecting command that may already have taken effect.",
].join("\n")

export default function (pi: ExtensionAPI) {
  const handler = async (args: string, ctx: ExtensionCommandContext) => {
    if (!ctx.isIdle()) {
      ctx.ui.notify("The agent is already running", "warning")
      return
    }
    const steer = args.trim()
    pi.sendMessage(
      { customType: COMMAND, content: steer ? `${NUDGE}\n\n${steer}` : NUDGE, display: false },
      { triggerTurn: true },
    )
  }
  pi.registerCommand(COMMAND, {
    description: "Resume after a cancel or error, or say yes to the agent's last proposal",
    handler,
  })
  pi.registerCommand(ALIAS, { description: `Alias of /${COMMAND}`, handler })
}
