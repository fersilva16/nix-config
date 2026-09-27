// opencode-style status line: cwd on the left, context and spend on the right.
// The store re-renders it when session state changes.
import { contextUsage, sessionCost } from "./core/store.ts"
import { homePath, shortTokens, spread } from "./core/style.ts"
import type { Ctx, Theme } from "./core/types.ts"

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: Ctx & { ui: Ui }) => void): void
}
type Ui = {
  setFooter(factory: (tui: unknown, theme: Theme) => { render(width: number): string[]; invalidate(): void }): void
}

export default function footer(pi: Pi) {
  pi.on("session_start", (_e, ctx) => {
    ctx.ui.setFooter((_tui, theme) => ({
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
    }))
  })
}
