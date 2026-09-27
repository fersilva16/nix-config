// opencode-style status line: cwd on the left, context and spend on the right.
import { type Ctx, contextUsage, homePath, sessionCost, shortTokens, spread, type Theme } from "./stats.ts"

type Tui = { requestRender(): void }
type Pi = {
  on(event: string, handler: (event: unknown, ctx: Ctx & { ui: Ui }) => void): void
}
type Ui = {
  setFooter(factory: (tui: Tui, theme: Theme) => { render(width: number): string[]; invalidate(): void }): void
}

export default function footer(pi: Pi) {
  let tui: Tui | undefined
  pi.on("session_start", (_e, ctx) => {
    ctx.ui.setFooter((t, theme) => {
      tui = t
      return {
        invalidate() {},
        render(width) {
          const { tokens, percent } = contextUsage(ctx)
          const usage = [
            tokens === undefined ? "" : `${shortTokens(tokens)}${percent === undefined ? "" : ` (${Math.round(percent)}%)`}`,
            `$${sessionCost(ctx.sessionManager.getBranch()).toFixed(2)}`,
          ]
            .filter(Boolean)
            .join(" · ")
          const right = `${theme.fg("muted", usage)}  ${theme.bold("ctrl+l")} ${theme.fg("muted", "models")}`
          return ["", spread(` ${theme.fg("muted", homePath(ctx.cwd))}`, `${right} `, width)]
        },
      }
    })
  })
  for (const event of ["turn_end", "model_select", "agent_settled"]) pi.on(event, () => tui?.requestRender())
}
