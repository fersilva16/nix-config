// /continue: re-run the agent from where a cancelled, errored or dropped turn
// stopped, with no new message. Same steps as omo's own auto-retry: drop the
// failed assistant turn from the agent's in-memory context (the session file
// keeps it, and it is never sent to the provider), then continue through the
// session's run lifecycle so the turn settles like any other. A turn that
// finished cleanly has nothing to continue, so that is just reported.
// /retry is the short alias.
//
// None of this is extension API. ctx.isIdle() reads the live session's isIdle
// getter, so the getter is wrapped for that one call to catch the instance;
// the rest are AgentSession internals, checked so an omo bump fails loudly.
import { AgentSession, type ExtensionAPI, type ExtensionCommandContext } from "@code-yeongyu/senpi"

const COMMAND = "continue"
const ALIAS = "retry"

type SessionInternals = {
  _isAgentRunActive: boolean
  _incrementMessageRevision(): void
  _scheduleContinuationAfterCurrentEvent(): void
}

function sessionOf(ctx: ExtensionCommandContext): AgentSession | undefined {
  const isIdle = Object.getOwnPropertyDescriptor(AgentSession.prototype, "isIdle")!
  let session: AgentSession | undefined
  Object.defineProperty(AgentSession.prototype, "isIdle", {
    ...isIdle,
    get(this: AgentSession) {
      session = this
      return isIdle.get!.call(this)
    },
  })
  try {
    ctx.isIdle()
  } finally {
    Object.defineProperty(AgentSession.prototype, "isIdle", isIdle)
  }
  return session
}

export default function (pi: ExtensionAPI) {
  const handler = async (_args: string, ctx: ExtensionCommandContext) => {
    const session = sessionOf(ctx)
    if (!session) {
      ctx.ui.notify(`/${COMMAND}: no in-process agent session to continue`, "error")
      return
    }
    if (!session.isIdle) {
      ctx.ui.notify("The agent is already running", "warning")
      return
    }
    const internals = session as unknown as SessionInternals
    if (
      typeof internals._isAgentRunActive !== "boolean" ||
      typeof internals._incrementMessageRevision !== "function" ||
      typeof internals._scheduleContinuationAfterCurrentEvent !== "function"
    ) {
      ctx.ui.notify(`/${COMMAND}: omo's AgentSession internals changed; update continue.ts`, "error")
      return
    }
    const { agent } = session
    const tail = agent.state.messages.at(-1)
    if (!tail || (tail.role === "assistant" && tail.stopReason !== "error" && tail.stopReason !== "aborted")) {
      ctx.ui.notify("Nothing to continue: the last turn finished cleanly", "info")
      return
    }
    if (tail.role === "assistant") {
      agent.state.messages = agent.state.messages.slice(0, -1)
      internals._incrementMessageRevision()
    }
    internals._isAgentRunActive = true
    internals._scheduleContinuationAfterCurrentEvent()
  }
  pi.registerCommand(COMMAND, {
    description: "Re-run the agent from where a cancelled or errored turn stopped",
    handler,
  })
  pi.registerCommand(ALIAS, { description: `Alias of /${COMMAND}`, handler })
}
