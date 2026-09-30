// opencode-style status line: cwd on the left, context and spend on the right.
// Extension statuses (ctx.ui.setStatus) sit between them when they fit, else
// on a line below. The store re-renders it when session state changes.
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui"
import { contextUsage, sessionCost } from "./core/store.ts"
import { homePath, shortTokens, spread } from "./core/style.ts"
import type { Ctx, Theme } from "./core/types.ts"

type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: Ctx & { ui: Ui }) => void): void
}
type FooterData = { getExtensionStatuses(): ReadonlyMap<string, string> }
type Ui = {
  setFooter(
    factory: (tui: unknown, theme: Theme, data: FooterData) => { render(width: number): string[]; invalidate(): void },
  ): void
}

function statuses(data: FooterData, theme: Theme): string {
  return [...data.getExtensionStatuses()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([, text]) => text.replace(/\s+/g, " ").trim())
    .filter(Boolean)
    .map((text) => theme.fg("muted", text))
    .join(theme.fg("dim", " · "))
}

export default function footer(pi: Pi) {
  pi.on("session_start", (_e, ctx) => {
    ctx.ui.setFooter((_tui, theme, data) => ({
      invalidate() {},
      render(width) {
        const { tokens, percent } = contextUsage(ctx)
        const usage = [
          tokens === undefined ? "" : `${shortTokens(tokens)}${percent === undefined ? "" : ` (${Math.round(percent)}%)`}`,
          `$${sessionCost(ctx.sessionManager.getBranch()).toFixed(2)}`,
        ]
          .filter(Boolean)
          .join(" · ")
        const left = ` ${theme.fg("muted", homePath(ctx.cwd))}`
        const right = `${theme.fg("muted", usage)}  ${theme.bold("ctrl+l")} ${theme.fg("muted", "models")} `
        const status = statuses(data, theme)
        if (!status) return ["", spread(left, right, width)]
        const inline = `${left}   ${status}`
        if (visibleWidth(inline) + visibleWidth(right) + 3 <= width) return ["", spread(inline, right, width)]
        return ["", spread(left, right, width), truncateToWidth(` ${status}`, width, theme.fg("dim", "…"))]
      },
    }))
  })
}
