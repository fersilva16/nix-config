// opencode-style modal backdrop. Terminals have no translucency, so while any
// capturing overlay is open the frame under it is repainted flat: every cell
// keeps its text but loses its colours to one dark fg/bg pair, which pushes
// the transcript back and makes the dialog the only thing that reads. It
// hooks the fullscreen renderer's compositeOverlays (omo internals), which
// receives the finished frame just before overlays land. While a frame is
// faded, sidebar.ts skips its per-row colour reset, which would otherwise cut
// the fade off at the transcript edge.
import { visibleWidth } from "@earendil-works/pi-tui"

// opencode's black-at-~60% scrim over Flexoki paper; the text under it is
// only a faint ghost (base600), so nothing behind the dialog competes with it.
const BG = "\x1b[48;2;94;93;89m"
const FG = "\x1b[38;2;111;110;105m"
const ESCAPES = /\x1b\[[0-9;:?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b_[^\x1b]*\x1b\\/g

export const BACKDROP = Symbol.for("omo-ui.backdrop")
const ORIGINAL = Symbol.for("omo-ui.backdrop.original")

type Composite = (screen: string[], width: number, height: number) => string[]
type Overlay = { options?: { nonCapturing?: boolean } }
type Tui = {
  layoutRoot?: unknown
  overlayStack?: Overlay[]
  isOverlayVisible?(entry: Overlay): boolean
  compositeOverlays?: Composite
  [ORIGINAL]?: Composite
}
type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: { ui: { setWidget(key: string, factory: (tui: Tui) => unknown): void } }) => void): void
}

function fade(screen: string[], width: number): string[] {
  return screen.map((line) => {
    const text = line.replace(ESCAPES, "")
    return `${BG}${FG}${text}${" ".repeat(Math.max(0, width - visibleWidth(text)))}\x1b[0m`
  })
}

// The unwrapped method lives on the tui under a global symbol, so /reload's
// fresh copy of this module re-wraps omo's original instead of stacking.
function install(tui: Tui) {
  const original = (tui[ORIGINAL] ??= tui.compositeOverlays)
  // Regular (non-fullscreen) mode has no layout root; leave it alone there.
  if (!original || !tui.layoutRoot) return
  const state = globalThis as { [BACKDROP]?: boolean }
  tui.compositeOverlays = function (this: Tui, screen, width, height) {
    const modal = (this.overlayStack ?? []).some((o) => !o.options?.nonCapturing && (this.isOverlayVisible?.(o) ?? true))
    state[BACKDROP] = modal
    return original.call(this, modal ? fade(screen, width) : screen, width, height)
  }
}

export default function backdrop(pi: Pi) {
  pi.on("session_start", (_e, ctx) => {
    ctx.ui.setWidget("ui-backdrop-mount", (tui) => {
      install(tui)
      return { render: () => [], invalidate() {} }
    })
  })
}
