// opencode's per-turn footer ("▣ agent · model · duration"), stored as a
// custom session entry: rendered in the transcript, never sent to the model.
import { Text } from "@earendil-works/pi-tui"
import { clock } from "./core/style.ts"
import type { Ctx, Theme } from "./core/types.ts"

const TYPE = "ui-turn"

type TurnData = { model: string; ms: number }
type Pi = {
  on(event: string, handler: (event: unknown, ctx: Ctx) => void): void
  appendEntry(customType: string, data: TurnData): void
  registerEntryRenderer(customType: string, render: (entry: { data?: TurnData }, options: unknown, theme: Theme) => unknown): void
}

export default function turn(pi: Pi) {
  let started: number | undefined

  pi.on("agent_start", () => {
    started ??= Date.now()
  })
  pi.on("agent_settled", (_e, ctx) => {
    if (started === undefined) return
    pi.appendEntry(TYPE, { model: ctx.model?.name ?? ctx.model?.id ?? "no model", ms: Date.now() - started })
    started = undefined
  })

  pi.registerEntryRenderer(TYPE, (entry, _options, theme) => {
    const data = entry.data ?? { model: "?", ms: 0 }
    const dot = theme.fg("dim", " · ")
    const duration = clock(Math.round(data.ms / 1000))
    return new Text(`${theme.fg("accent", "▣")}  OmO${dot}${theme.fg("muted", data.model)}${dot}${theme.fg("muted", duration)}`, 1, 0)
  })
}
