// The one module that touches omo internals: anything the extension API does
// not cover (the fullscreen layout root, frame compositing, text selection,
// tool rows). Feature files call these helpers, so an omo upgrade that moves
// an internal breaks here and nowhere else.
import { ToolExecutionComponent } from "@code-yeongyu/senpi"
import type { Component, Theme, Tui } from "./types.ts"

type Method = (this: any, ...args: any[]) => any

// Wraps target[name]. The unwrapped method is kept on the target under a
// global symbol, so /reload's fresh copy of this module re-wraps omo's
// original instead of stacking wrappers.
export function patch(target: object, name: string, wrap: (original: Method) => Method): void {
  const slots = target as Record<string | symbol, Method | undefined>
  const key = Symbol.for(`omo-ui.original.${name}`)
  const original = (slots[key] ??= slots[name])
  if (original) slots[name] = wrap(original)
}

type HostTui = Tui & {
  layoutRoot?: Component
  setLayoutRoot?(root: Component | undefined): void
  applySelection?: Method
  compositeOverlays?: Method
  overlayStack?: { options?: { nonCapturing?: boolean } }[]
  isOverlayVisible?(entry: unknown): boolean
}
type Mount = (tui: HostTui, theme: Theme) => void
type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: { ui: { setWidget(key: string, factory: (tui: HostTui, theme: Theme) => Component): void } }) => void): void
}

let tui: HostTui | undefined
const mounts: Mount[] = []

// Widget factories are the only API that hands out the tui; one empty widget
// passes it to every feature that needs it.
export function initHost(pi: Pi): void {
  pi.on("session_start", (_e, ctx) => {
    ctx.ui.setWidget("ui-host-mount", (t, theme) => {
      tui = t
      for (const mount of mounts) mount(t, theme)
      return { render: () => [], invalidate() {} }
    })
  })
}

export function onTui(mount: Mount): void {
  mounts.push(mount)
}

export function requestRender(): void {
  tui?.requestRender()
}

// Fullscreen layout. Only fullscreen mode has a layout root; in regular mode
// these hooks are no-ops.
const INNER = Symbol.for("omo-ui.layout.inner")
let wrapped: Component | undefined

// /new and /reload re-run session_start, so the root may already be a
// previous wrapper; the wrapper records omo's own root under INNER, which
// survives module reloads, and it is unwrapped before wrapping again.
// Returns whether the tui is fullscreen (has a layout root).
export function wrapLayout(t: HostTui, build: (inner: Component) => Component): boolean {
  const current = t.layoutRoot as (Component & { [INNER]?: Component }) | undefined
  if (!t.setLayoutRoot || !current) return false
  if (current === wrapped) return true
  const inner = current[INNER] ?? current
  wrapped = Object.assign(build(inner), { [INNER]: inner })
  t.setLayoutRoot(wrapped)
  return true
}

export function afterSelection(t: HostTui, after: (lines: string[]) => string[]): void {
  patch(t, "applySelection", (original) =>
    function (this: HostTui, screen: string[], layout?: unknown) {
      return after(original.call(this, screen, layout))
    },
  )
}

let modalFrame = false

// True while the frame being drawn has a capturing overlay on top.
export function isModalFrame(): boolean {
  return modalFrame
}

// Rewrites the finished frame just before overlays are composited onto it.
export function beforeOverlays(t: HostTui, rewrite: (screen: string[], width: number, modal: boolean) => string[]): void {
  if (!t.layoutRoot) return
  patch(t, "compositeOverlays", (original) =>
    function (this: HostTui, screen: string[], width: number, height: number) {
      modalFrame = (this.overlayStack ?? []).some((o) => !o.options?.nonCapturing && (this.isOverlayVisible?.(o) ?? true))
      return original.call(this, rewrite(screen, width, modalFrame), width, height)
    },
  )
}

// Tool rows. omo has no API for restyling rows or replacing another
// extension's tool renderer. Every row is a ToolExecutionComponent that keeps
// its tool definition on `identity` and reads renderCall/renderResult from it
// on each render, so wrapping the shared prototype's render reaches them all.
export type ToolRow = {
  isPartial: boolean
  result?: { isError?: boolean }
  identity: { toolName: string; toolCallId: string; toolDefinition?: Partial<Renderers> }
  invalidate(): void
}
type Renderers = { renderCall: Method; renderResult: Method }
type RowHook = (row: ToolRow, render: (width: number) => string[], width: number) => string[]

let rowHook: RowHook | undefined
const rendererSwaps = new Map<string, (original: Renderers) => Renderers>()
const swapped = new WeakSet<object>()
const refreshed = new WeakSet<ToolRow>()

export function onToolRow(hook: RowHook): void {
  rowHook = hook
  patchRows()
}

export function replaceToolRenderers(toolName: string, make: (original: Renderers) => Renderers): void {
  rendererSwaps.set(toolName, make)
  patchRows()
}

// Rows restored with a session may have rendered (and cached) before the swap,
// so each affected row is invalidated once to rebuild with the new renderers.
function swapRenderers(row: ToolRow): void {
  const make = rendererSwaps.get(row.identity.toolName)
  const def = row.identity.toolDefinition
  if (!make || !def?.renderCall || !def.renderResult || refreshed.has(row)) return
  if (!swapped.has(def)) {
    Object.assign(def, make({ renderCall: def.renderCall, renderResult: def.renderResult }))
    swapped.add(def)
  }
  refreshed.add(row)
  row.invalidate()
}

function patchRows(): void {
  patch(ToolExecutionComponent.prototype, "render", (original) =>
    function (this: ToolRow, width: number) {
      swapRenderers(this)
      const render = (w: number): string[] => original.call(this, w)
      return rowHook ? rowHook(this, render, width) : render(width)
    },
  )
}
