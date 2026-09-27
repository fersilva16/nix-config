// opencode-style dialogs: a centred overlay on a filled panel (the dimmed
// backdrop comes from backdrop.ts). `modalFrame` draws the panel rows,
// `openModal` shows any component in one, `confirm` is a ready-made dialog.
import { Key, matchesKey, truncateToWidth } from "@earendil-works/pi-tui"
import { fill, sgr, spread } from "./style.ts"
import type { Component, Theme, Tui } from "./types.ts"

// opencode's "large" dialog: 88 columns, a one-column margin around the
// highlight bar, and text inset three more columns inside it.
export const MODAL_WIDTH = 88
const EDGE = 1
const INDENT = 3
const PANEL = "userMessageBg"

type ModalCtx = {
  ui: {
    custom<T>(
      factory: (tui: Tui, theme: Theme, keybindings: unknown, done: (value: T) => void) => Component,
      options: { overlay: true; overlayOptions: () => Record<string, unknown> },
    ): Promise<T>
  }
}

export function openModal<T>(ctx: ModalCtx, factory: (tui: Tui, theme: Theme, done: (value: T) => void) => Component, width = MODAL_WIDTH): Promise<T> {
  let columns = width + 4
  return ctx.ui.custom<T>(
    (tui, theme, _keys, done) => {
      columns = tui.terminal.columns
      return factory(tui, theme, done)
    },
    { overlay: true, overlayOptions: () => ({ width: Math.min(width, columns - 4), anchor: "center" }) },
  )
}

export type Hint = [label: string, keys: string]

export function modalFrame(theme: Theme, width: number) {
  const panel = sgr(theme, PANEL, "bg")
  const inset = EDGE + INDENT
  const inner = Math.max(1, width - 2 * inset)
  const line = (text = "") => fill(panel, `${" ".repeat(inset)}${truncateToWidth(text, inner)}`, width)
  return {
    inner,
    line,
    header: (title: string) => line(spread(theme.bold(title), theme.fg("muted", "esc"), inner)),
    hints: (hints: Hint[]) => hints.map(([label, keys]) => `${label} ${theme.fg("muted", keys)}`).join("   "),
    // A full-width bar in `token`'s colour with bold panel-coloured text, as
    // opencode draws the selected row.
    highlight: (token: string, text: string) => {
      const bar = fill(sgr(theme, token, "fg", "bg"), `${" ".repeat(INDENT)}${truncateToWidth(`${sgr(theme, PANEL, "bg", "fg")}\x1b[1m${text}`, inner)}`, width - 2 * EDGE)
      return fill(panel, `${" ".repeat(EDGE)}${bar}`, width)
    },
  }
}

export type ConfirmAction<T> = { key: string; label: string; value: T }

// Resolves with the chosen action's value, or undefined on esc.
export function confirm<T>(ctx: ModalCtx, options: { title: string; message: string; actions: ConfirmAction<T>[]; width?: number }): Promise<T | undefined> {
  const { title, message, actions } = options
  return openModal<T | undefined>(
    ctx,
    (_tui, theme, done) => ({
      render(width) {
        const f = modalFrame(theme, width)
        return [
          f.line(),
          f.header(title),
          f.line(),
          ...message.split("\n").map((text) => f.line(text)),
          f.line(),
          f.line(f.hints(actions.map((a) => [a.label, a.key]))),
          f.line(),
        ]
      },
      invalidate() {},
      handleInput(data) {
        if (matchesKey(data, Key.escape)) return done(undefined)
        const action = actions.find((a) => matchesKey(data, a.key))
        if (action) done(action.value)
      },
    }),
    options.width ?? 60,
  )
}
