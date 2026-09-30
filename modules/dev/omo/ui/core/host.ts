// The one module that touches omo internals: anything the extension API does
// not cover (the fullscreen layout root, frame compositing, text selection,
// tool rows). Feature files call these helpers, so an omo upgrade that moves
// an internal breaks here and nowhere else.
import { ExtensionRunner, highlightCode, InteractiveMode, ToolExecutionComponent } from "@code-yeongyu/senpi"
import { Markdown, TuiAltScreen } from "@earendil-works/pi-tui"
import type { Component, Theme, Tui } from "./types.ts"

type Method = (this: any, ...args: any[]) => any

// Wraps target[name]. The unwrapped method is kept on the target under a
// global symbol, so /reload's fresh copy of this module re-wraps omo's
// original instead of stacking wrappers.
//
// A running omo can /reload into a newer copy of this extension, so a key
// must never be renamed: the new copy would take the old wrapper for omo's
// original and wrap on top of it. Keys used before core/host.ts existed are
// listed here and still count.
const LEGACY_ORIGINALS: Record<string, symbol | undefined> = {
  applySelection: Symbol.for("omo-ui-sidebar.applySelection"),
  compositeOverlays: Symbol.for("omo-ui.backdrop.original"),
  render: Symbol.for("omo-ui-tools.render"),
}

export function patch(target: object, name: string, wrap: (original: Method) => Method): void {
  const slots = target as Record<string | symbol, Method | undefined>
  const key = Symbol.for(`omo-ui.original.${name}`)
  const legacy = LEGACY_ORIGINALS[name]
  const original = (slots[key] ??= (legacy && slots[legacy]) ?? slots[name])
  if (original) slots[name] = wrap(original)
}

type HostTui = Tui & {
  layoutRoot?: Component
  setLayoutRoot?(root: Component | undefined): void
  applySelection?: Method
  compositeOverlays?: Method
  overlayStack?: { options?: { nonCapturing?: boolean } }[]
  isOverlayVisible?(entry: unknown): boolean
  hasActiveSelection?(): boolean
  copyActiveSelectionToClipboard?(): Promise<boolean>
  clearTextSelection?(): void
}
type Mount = (tui: HostTui, theme: Theme) => void
type Pi = {
  on(event: "session_start", handler: (event: unknown, ctx: { ui: { setWidget(key: string, factory: (tui: HostTui, theme: Theme) => Component): void } }) => void): void
}

let tui: HostTui | undefined
const mounts: Mount[] = []

// Widget factories are the only API that hands out the tui; one empty widget
// passes it to every feature that needs it. omo can run the extension again
// without re-importing this module (/new, session switch), so mounts from the
// previous run are dropped rather than kept alongside the new ones.
export function initHost(pi: Pi): void {
  mounts.length = 0
  pi.on("session_start", (_e, ctx) => {
    ctx.ui.setWidget("ui-host-mount", (t, theme) => {
      if (isRpcProxy(t)) return { render: () => [], invalidate() {} }
      tui = t
      for (const mount of mounts) mount(t, theme)
      return { render: () => [], invalidate() {} }
    })
  })
}

// On the shared RPC host (experimental.sharedHost) the host process renders
// widget factories against a proxy tui that throws on any internal member
// ("RPC live component TUI member is unsupported: layoutRoot"), and that throw
// fails whichever tool triggered the render (todo, ask-user). The TUI client
// runs this extension against its real tui, so the host side just skips.
function isRpcProxy(t: HostTui): boolean {
  try {
    void t.layoutRoot
    return false
  } catch {
    return true
  }
}

export function onTui(mount: Mount): void {
  mounts.push(mount)
}

export function requestRender(): void {
  tui?.requestRender()
}

// Copies the fullscreen mouse selection and clears it, so the next press of
// the same key acts normally. False when nothing is selected.
export function copySelection(): boolean {
  if (!tui?.hasActiveSelection?.()) return false
  void tui.copyActiveSelectionToClipboard?.()
  tui.clearTextSelection?.()
  tui.requestRender()
  return true
}

// Fullscreen layout. Only fullscreen mode has a layout root; in regular mode
// these hooks are no-ops.
const INNER = Symbol.for("omo-ui.layout.inner")
// The key sidebar.ts used before core/host.ts existed (see patch()).
const LEGACY_INNER = Symbol.for("omo-ui-sidebar.inner")
type Wrapper = Component & { [INNER]?: Component; [LEGACY_INNER]?: Component }

// omo's own root under any chain of our wrappers.
const unwrap = (root: Wrapper): Component => {
  const inner = root[INNER] ?? root[LEGACY_INNER]
  return inner ? unwrap(inner) : root
}

// /new, /reload and session switches re-run session_start, so the root may
// already be a wrapper, possibly built by another copy of this extension or
// by an earlier run whose state is gone. The wrapper records omo's own root
// under INNER, which survives module reloads; every call unwraps to it and
// wraps again with the caller's build, so the latest mount always wins.
// Returns whether the tui is fullscreen (has a layout root).
export function wrapLayout(t: HostTui, build: (inner: Component) => Component): boolean {
  const current = t.layoutRoot as Wrapper | undefined
  if (!t.setLayoutRoot || !current) return false
  const inner = unwrap(current)
  t.setLayoutRoot(Object.assign(build(inner), { [INNER]: inner }))
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

export type RowRenderers = Partial<Renderers> & { renderShell?: string }
type MatchedMake = (original: RowRenderers, toolName: string) => Renderers
let matchedSwap: { match: (toolName: string) => boolean; make: MatchedMake } | undefined

// Like replaceToolRenderers, for every tool `match` accepts that has no
// replaceToolRenderers swap, including tools without renderers of their own
// (`original` then lacks them and omo would draw its plain fallback). A later
// call replaces the earlier one. `renderShell: "self"` means the tool draws
// its own box, and the swapped renderers must too.
export function replaceToolRenderersWhere(match: (toolName: string) => boolean, make: MatchedMake): void {
  matchedSwap = { match, make }
  patchRows()
}

// Built-in tools can share omo's renderer objects, which also draw the nested
// calls in eval rows, so these swaps go on a per-row copy of the definition.
// The row keeps omo's definition under ROW_DEFINITION, so after /reload the
// new copy of this module swaps from it rather than from the old copy.
const ROW_DEFINITION = Symbol.for("omo-ui.tool-row.definition")
function swapMatched(row: ToolRow): void {
  const identity = row.identity as ToolRow["identity"] & { [ROW_DEFINITION]?: RowRenderers }
  const def = (identity[ROW_DEFINITION] ??= identity.toolDefinition as RowRenderers | undefined)
  if (!def || !matchedSwap?.match(identity.toolName) || refreshed.has(row)) return
  identity.toolDefinition = { ...def, ...matchedSwap.make(def, identity.toolName) }
  refreshed.add(row)
  row.invalidate()
}

// Rows restored with a session may have rendered (and cached) before the swap,
// so each affected row is invalidated once to rebuild with the new renderers.
function swapRenderers(row: ToolRow): void {
  const make = rendererSwaps.get(row.identity.toolName)
  const def = row.identity.toolDefinition
  if (!make) return swapMatched(row)
  if (!def?.renderCall || !def.renderResult || refreshed.has(row)) return
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

// Exploration groups. omo folds each run of read/grep/find/ls rows that keep
// their stock renderers into an ExplorationGroup, which draws a summary
// instead of the rows until they are expanded. Neither the group class nor
// the transcript container that builds groups is exported: the container is
// InteractiveMode's chatContainer, reached when omo creates a tool row, and
// its render reaches the group class once a group exists. The hook draws
// collapsed groups; undefined leaves one to omo.
export type RowSnapshot = {
  toolName: string
  cwd: string
  args: Record<string, unknown>
  isPartial: boolean
  result?: { content?: { type: string; text?: string; audience?: string }[]; details?: Record<string, unknown>; isError?: boolean }
}
type GroupHook = (calls: RowSnapshot[], rules: number, width: number) => string[] | undefined
type Snapshotted = { presentationSnapshot: { identity: { toolName: string; cwd: string }; state: Omit<RowSnapshot, "toolName" | "cwd"> } }
type Group = Component & { calls: { component: Snapshotted }[]; rules: unknown[]; expanded: boolean }
type GroupContainer = Component & { display?: { children?: unknown[] } }

let groupHook: GroupHook | undefined
let containerPatched = false
let groupPatched = false

export function onExplorationGroup(hook: GroupHook): void {
  groupHook = hook
  patch(InteractiveMode.prototype as object, "createToolExecutionComponent", (original) =>
    function (this: { chatContainer?: object }, ...args: unknown[]) {
      if (!containerPatched && this.chatContainer) patchContainer(Object.getPrototypeOf(this.chatContainer))
      return original.apply(this, args)
    },
  )
}

function patchContainer(proto: object): void {
  containerPatched = true
  patch(proto, "render", (original) =>
    function (this: GroupContainer, width: number) {
      const lines = original.call(this, width)
      const group = groupPatched ? undefined : this.display?.children?.find(isGroup)
      if (!group) return lines
      patchGroup(Object.getPrototypeOf(group))
      return original.call(this, width)
    },
  )
}

function isGroup(c: unknown): c is Group {
  const g = c as (Partial<Group> & { setMembers?: unknown }) | undefined
  return typeof g?.setMembers === "function" && Array.isArray(g.calls)
}

function patchGroup(proto: object): void {
  groupPatched = true
  patch(proto, "render", (original) =>
    function (this: Group, width: number) {
      if (!groupHook || this.expanded) return original.call(this, width)
      const calls = this.calls.map(({ component }) => {
        const { identity, state } = component.presentationSnapshot
        return { ...state, toolName: identity.toolName, cwd: identity.cwd }
      })
      return groupHook(calls, new Set(this.rules).size, width) ?? original.call(this, width)
    },
  )
}

// Notices, header and widgets (sidebar). omo appends status lines, warnings
// and notice boxes straight to the transcript from InteractiveMode methods,
// with no API to redirect them. Each hook wraps the method on the prototype;
// a hook that returns true takes the item and omo's method is skipped.
export type Notice = { kind: "status" | "warning" | "error"; title?: string; text: string }
type NoticeBox = { title: string; tone?: string; why: string; extra?: { text: string }[] }
const mode = InteractiveMode.prototype as object

export function onNotice(take: (notice: Notice) => boolean): void {
  const route = <A extends unknown[]>(name: string, toNotice: (...args: A) => Notice | undefined) =>
    patch(mode, name, (original) =>
      function (this: unknown, ...args: A) {
        const notice = toNotice(...args)
        if (!notice || !take(notice)) return original.apply(this, args)
      },
    )
  route("showStatus", (text: string) => ({ kind: "status", text }))
  route("showWarning", (text: string) => ({ kind: "warning", text }))
  route("showNoticeBox", (box: NoticeBox) => ({
    kind: box.tone === "error" ? "error" : "warning",
    title: box.title,
    text: [box.why, ...(box.extra ?? []).map((l) => l.text)].join("\n"),
  }))
  // showError also carries turn errors, which stay in the transcript; only
  // ctx.ui.notify(…, "error") is taken, before it reaches showError. Other
  // notify levels land in the showStatus/showWarning wrappers above.
  route("showExtensionNotify", (text: string, type?: string) => (type === "error" ? { kind: "error", text } : undefined))
}

// ctx.ui.notify, before it becomes a status, warning or error. A method takes
// one wrapper and onNotice holds showExtensionNotify, so the notify of each
// extension UI context is wrapped where omo builds the context. The context
// has getters (theme), so it is changed in place rather than copied. omo
// builds a context before /reload loads the new extensions, so a context can
// outlive the copy of this module that wrapped it; each call asks for the
// latest hook, kept on the prototype under a global symbol.
type NotifyHook = (message: string, type?: string) => boolean
const NOTIFY = Symbol.for("omo-ui.notify.hook")

export function onNotify(take: NotifyHook): void {
  const slots = mode as { [NOTIFY]?: NotifyHook }
  slots[NOTIFY] = take
  patch(mode, "createExtensionUIContext", (original) =>
    function (this: unknown, ...args: unknown[]) {
      const ui: { notify(message: string, type?: string): void } = original.apply(this, args)
      const notify = ui.notify
      ui.notify = (message, type) => {
        if (!slots[NOTIFY]?.(message, type)) notify(message, type)
      }
      return ui
    },
  )
}

export function onUpdate(take: (version: string) => boolean): void {
  patch(mode, "showNewVersionNotification", (original) =>
    function (this: unknown, version: string) {
      if (!take(version)) return original.call(this, version)
    },
  )
}

// Header factories are rendered once with an unstyled theme so the hook can
// read their text; undefined means the header is being cleared.
const PLAIN = new Proxy({}, { get: () => (...args: string[]) => args.at(-1) }) as Theme
export function onHeader(take: (text: string | undefined) => boolean): void {
  patch(mode, "setExtensionHeader", (original) =>
    function (this: { ui: unknown }, factory?: (tui: unknown, theme: Theme) => Component) {
      const text = factory?.(this.ui, PLAIN).render(200).join("\n")
      return original.call(this, take(text) ? undefined : factory)
    },
  )
}

// A taken widget is removed instead of set, so omo's copy never shows.
export function onWidget(key: string, take: () => boolean): void {
  onWidgetContent(key, (content) => (take() ? undefined : content))
}

// Widgets any extension sets above or below the prompt (ctx.ui.setWidget).
// The hook sees every set (and clear, as undefined) of its key and returns
// what omo shows instead: the same content, a restyled factory, or undefined
// for nothing. One hook per key; all share one wrap of setExtensionWidget.
export type WidgetContent = string[] | ((tui: Tui, theme: Theme) => Component)
type WidgetHook = (content: WidgetContent | undefined) => WidgetContent | undefined
const widgetHooks = new Map<string, WidgetHook>()

export function onWidgetContent(key: string, hook: WidgetHook): void {
  widgetHooks.set(key, hook)
  patch(mode, "setExtensionWidget", (original) =>
    function (this: unknown, k: string, content: WidgetContent | undefined, options: unknown) {
      const hook = widgetHooks.get(k)
      return original.call(this, k, hook ? hook(content) : content, options)
    },
  )
}

// Transcript entries. A custom message or entry is drawn by the renderer the
// first-loaded extension registered for its type, and omo's built-in
// extensions load before this one, so registering our own never wins.
// ExtensionRunner looks the renderer up each time an item is added to the
// transcript; the hook may replace what the lookup returns (undefined keeps
// omo's, which may itself be undefined: a message with no renderer).
export type CustomRenderer = (item: never, options: { expanded: boolean }, theme: Theme) => Component | undefined
type RendererHook = (kind: "message" | "entry", customType: string, original: CustomRenderer | undefined) => CustomRenderer | undefined

export function onCustomRenderer(hook: RendererHook): void {
  const route = (name: string, kind: "message" | "entry") =>
    patch(ExtensionRunner.prototype as object, name, (original) =>
      function (this: unknown, customType: string) {
        const renderer: CustomRenderer | undefined = original.call(this, customType)
        return hook(kind, customType, renderer) ?? renderer
      },
    )
  route("getMessageRenderer", "message")
  route("getEntryRenderer", "entry")
}

// Markdown code blocks. Markdown.renderCodeBlock(lines, code, lang, indent)
// pushes a ``` fence, the highlighted lines and a closing fence; it is not
// given the width, so renderToken(token, width, ...) (which calls it, and
// recurses for lists and quotes) records the width it was called with.
export type CodeBlock = {
  code: string
  lang: string | undefined
  width: number
  // Syntax-highlighted lines: omo's cached highlighter through the markdown
  // theme, or the exported highlightCode when the theme has none.
  highlight(): string[]
}
type CodeBlockHook = (block: CodeBlock) => string[] | undefined
type MarkdownInternals = {
  theme: { highlightCode?: unknown; codeBlock(text: string): string }
  highlightCodeBlock(code: string, lang: string | undefined): string[] | undefined
  [TOKEN_WIDTH]?: number
}

const TOKEN_WIDTH = Symbol.for("omo-ui.markdown.width")
let codeBlockHook: CodeBlockHook | undefined

export function onCodeBlock(hook: CodeBlockHook): void {
  codeBlockHook = hook
  const proto = Markdown.prototype as object
  patch(proto, "renderToken", (original) =>
    function (this: MarkdownInternals, token: unknown, width: number, ...rest: unknown[]) {
      const outer = this[TOKEN_WIDTH]
      this[TOKEN_WIDTH] = width
      try {
        return original.call(this, token, width, ...rest)
      } finally {
        this[TOKEN_WIDTH] = outer
      }
    },
  )
  patch(proto, "renderCodeBlock", (original) =>
    function (this: MarkdownInternals, lines: string[], code: string, lang: string | undefined, indent: string) {
      const width = this[TOKEN_WIDTH]
      const highlight = () =>
        this.highlightCodeBlock(code, lang) ??
        // No theme highlighter, or the block is over omo's highlight cap.
        (this.theme.highlightCode ? code.split("\n").map((l) => this.theme.codeBlock(l)) : highlightCode(code, lang))
      const rendered = width === undefined ? undefined : codeBlockHook?.({ code, lang, width, highlight })
      if (rendered) lines.push(...rendered)
      else original.call(this, lines, code, lang, indent)
    },
  )
}

// Copying a mouse selection. TuiAltScreen.getActiveSelectionText slices the
// rendered rows by column and strips escapes, so any chrome glyph we draw is
// copied; the hook rewrites that plain text before it reaches the clipboard.
export function onSelectionText(rewrite: (text: string) => string): void {
  patch(TuiAltScreen.prototype as object, "getActiveSelectionText", (original) =>
    function (this: unknown) {
      const text: string | undefined = original.call(this)
      return text === undefined ? undefined : rewrite(text) || undefined
    },
  )
}

// Extension dialogs: ctx.ui.select (and confirm, a Yes/No select), input and
// editor. omo builds the dialog component and puts it in the editor's place;
// right after, the hook gets it and returns a component drawn in its place as
// a centred overlay, which forwards keys to omo's so its keys, countdown and
// answer stay omo's. The editor goes back under the overlay, and omo's hide
// methods close the overlay.
type Labeled = { text: string }
export type ExtensionDialog =
  | {
      kind: "select"
      title: string
      stock: Component & { options: string[]; selectedIndex: number; maxVisibleOptions: number; titleText: Labeled }
    }
  | { kind: "input"; title: string; stock: Component & { input: Component; titleText: Labeled } }
  | { kind: "editor"; title: string; stock: Component & { editor: Component } }
type DialogKind = ExtensionDialog["kind"]
type DialogHook = (dialog: ExtensionDialog, tui: Tui) => { component: Component; width: number } | undefined
type Overlay = { hide(): void }
const DIALOG_OVERLAYS = Symbol.for("omo-ui.dialog.overlays")
type DialogHost = {
  ui: HostTui & { showOverlay(component: Component, options: Record<string, unknown>): Overlay }
  editor: Component
  editorContainer: { detachAll(): void; addChild(component: Component): void }
  extensionSelector?: Component
  extensionInput?: Component
  extensionEditor?: Component
  [DIALOG_OVERLAYS]?: Partial<Record<DialogKind, { overlay: Overlay; stock: Component & { dispose?(): void } }>>
}
const DIALOGS: Record<DialogKind, [show: string, hide: string, field: "extensionSelector" | "extensionInput" | "extensionEditor"]> = {
  select: ["showExtensionSelector", "hideExtensionSelector", "extensionSelector"],
  input: ["showExtensionInput", "hideExtensionInput", "extensionInput"],
  editor: ["showExtensionEditor", "hideExtensionEditor", "extensionEditor"],
}

let dialogHook: DialogHook | undefined

export function onDialog(present: DialogHook): void {
  dialogHook = present
  for (const [kind, [show, hide, field]] of Object.entries(DIALOGS) as [DialogKind, (typeof DIALOGS)[DialogKind]][]) {
    patch(mode, show, (original) =>
      function (this: DialogHost, title: string, ...rest: unknown[]) {
        const before = this[field]
        const result = original.call(this, title, ...rest)
        const stock = this[field]
        if (stock && stock !== before) presentDialog(this, { kind, title, stock } as ExtensionDialog)
        return result
      },
    )
    patch(mode, hide, (original) =>
      function (this: DialogHost, ...args: unknown[]) {
        closeDialog(this, kind)
        return original.apply(this, args)
      },
    )
  }
}

function closeDialog(host: DialogHost, kind: DialogKind, dispose = false): void {
  const overlays = host[DIALOG_OVERLAYS]
  const open = overlays?.[kind]
  if (!overlays || !open) return
  open.overlay.hide()
  if (dispose) open.stock.dispose?.()
  delete overlays[kind]
}

// Clearing a container disposes its children, which stops omo's countdown,
// so the dialog is detached from the editor's place instead. A new dialog
// replaces whichever one was up, as omo's own clear() would, and disposes it.
function presentDialog(host: DialogHost, dialog: ExtensionDialog): void {
  const shown = dialogHook?.(dialog, host.ui)
  if (!shown) return
  for (const kind of Object.keys(DIALOGS) as DialogKind[]) closeDialog(host, kind, true)
  host.editorContainer.detachAll()
  host.editorContainer.addChild(host.editor)
  const width = Math.min(shown.width, host.ui.terminal.columns - 4)
  const overlay = host.ui.showOverlay(shown.component, { width, anchor: "center" })
  ;(host[DIALOG_OVERLAYS] ??= {})[dialog.kind] = { overlay, stock: dialog.stock }
}

// Built-in pickers (/model, /thinking, /scoped-models, /favorite-models, and
// any other omo selector). omo builds each one through showSelector, which
// puts it in the editor's place. A hook registered for the component's class
// name gets it right after and returns a component drawn in its place as a
// centred overlay; that component forwards keys to omo's, so selection,
// saving and favorites stay omo's. The picker's own close (done) and
// disposeActiveSelector (a replacing picker, session switch) hide it.
// Undefined, or no hook for the class, leaves omo's picker as is.
export type Selector = { name: string; stock: Component & { focused?: boolean } }
type SelectorHook = (selector: Selector, tui: Tui) => { component: Component; width: number } | undefined
type Created = { component: Component; focus: Component; dispose?: () => void }
type SelectorHost = DialogHost & { ui: { setFocus(component: Component): void }; [SELECTOR_OVERLAY]?: Overlay }
const SELECTOR_OVERLAY = Symbol.for("omo-ui.selector.overlay")
const selectorHooks = new Map<string, SelectorHook>()

export function onSelector(name: string, present: SelectorHook): void {
  selectorHooks.set(name, present)
  patch(mode, "disposeActiveSelector", (original) =>
    function (this: SelectorHost, ...args: unknown[]) {
      this[SELECTOR_OVERLAY]?.hide()
      delete this[SELECTOR_OVERLAY]
      return original.apply(this, args)
    },
  )
  patch(mode, "showSelector", (original) =>
    function (this: SelectorHost, create: (done: () => void) => Created) {
      let stock: Component | undefined
      let overlay: Overlay | undefined
      const result = original.call(this, (done: () => void) => {
        const created = create(() => {
          overlay?.hide()
          if (this[SELECTOR_OVERLAY] === overlay) delete this[SELECTOR_OVERLAY]
          done()
        })
        stock = created.component
        return created
      })
      const name = stock?.constructor?.name ?? ""
      const shown = stock && selectorHooks.get(name)?.({ name, stock }, this.ui)
      if (!shown) return result
      this.editorContainer.detachAll()
      this.editorContainer.addChild(this.editor)
      // The overlay hands focus back to the editor, not the detached picker.
      this.ui.setFocus(this.editor)
      const width = Math.min(shown.width, this.ui.terminal.columns - 4)
      overlay = this.ui.showOverlay(shown.component, { width, anchor: "center" })
      this[SELECTOR_OVERLAY] = overlay
      return result
    },
  )
}

// /rename and /name without a name (and app.session.renameCurrent) put an
// ExtensionInputComponent in the editor's place directly, not through
// showExtensionInput, so onDialog never sees it. This hands it to the same
// dialog hook; omo's hideExtensionInput closes it as for any input dialog.
export function renameAsDialog(): void {
  patch(mode, "showSessionRenameInput", (original) =>
    function (this: DialogHost, ...args: unknown[]) {
      const before = this.extensionInput
      const result = original.apply(this, args)
      const stock = this.extensionInput
      if (stock && stock !== before) presentDialog(this, { kind: "input", title: "Rename session", stock } as ExtensionDialog)
      return result
    },
  )
}

// Thinking level changes (shift+tab, /thinking). omo reports each one as a
// "Thinking level: x" status line; a hook that returns true takes it instead
// (`saved` when it was also made the default), and omo still repaints the
// footer and editor border.
type ThinkingHost = {
  isInitialized?: boolean
  footer: { invalidate(): void }
  updateEditorBorderColor(): void
  showStatus(text: string): void
}
let thinkingHook: ((level: string, saved: boolean) => boolean) | undefined

export function onThinkingChange(take: (level: string, saved: boolean) => boolean): void {
  thinkingHook = take
  patch(mode, "handleEvent", (original) =>
    function (this: ThinkingHost, event: { type?: string; level?: string }, ...rest: unknown[]) {
      if (event?.type !== "thinking_level_changed" || !this.isInitialized || !event.level || !thinkingHook?.(event.level, false)) {
        return original.call(this, event, ...rest)
      }
      this.footer.invalidate()
      this.updateEditorBorderColor()
    },
  )
  // Picking a level also emits the event above, then writes its own status;
  // that second status is taken here, marking a level saved with ctrl+s.
  patch(mode, "selectThinkingLevel", (original) =>
    function (this: ThinkingHost, level: string, persist: boolean, ...rest: unknown[]) {
      const show = this.showStatus
      this.showStatus = function (this: ThinkingHost, text: string) {
        if (!text.endsWith(`hinking level: ${level}`) || !thinkingHook?.(level, !!persist)) show.call(this, text)
      }
      try {
        return original.call(this, level, persist, ...rest)
      } finally {
        delete (this as Partial<ThinkingHost>).showStatus
      }
    },
  )
}

// Questions. The ask-user tool has no styling API. A blocking question (or
// an expanded non-blocking one) replaces the editor with an
// AskUserQuestionComponent that InteractiveMode keeps on `askUserQuestion`;
// a pending non-blocking question is the "ask-user" widget that
// refreshAsyncWidget sets above the editor. All of it happens inside
// InteractiveMode methods, which are wrapped once here; the exported hooks
// only switch features on.
export type QuestionComponent = Component & {
  children: Component[]
  titleText: Component
  hintsText: Component & { text: string }
  countdownLabel: string
  doneCallback(response: { status: string }): void
  state: {
    focus: string
    activeTabIndex: number
    activeQuestion: { header: string }
    request: { questions: unknown[] }
  }
}
type QuestionHost = {
  askUserQuestion?: QuestionComponent
  setExtensionWidget: Method
  shownQuestionId?: string
  pendingOrder: string[]
  pendingQuestions: Map<string, { finish(response: unknown): void }>
  ui: { hasOverlay(): boolean }
  extensionSelector?: unknown
  extensionInput?: unknown
  extensionEditor?: unknown
  expandPendingQuestion(requestId?: string, ...rest: unknown[]): boolean
}
type WidgetFactory = (...args: unknown[]) => Component

const questionHooks: {
  decorate?: (question: QuestionComponent) => void
  decorateWidget?: (widget: Component) => Component
  expandPending?: boolean
} = {}

export function onQuestion(decorate: (question: QuestionComponent) => void): void {
  questionHooks.decorate = decorate
  patchQuestions()
}

export function onQuestionWidget(decorate: (widget: Component) => Component): void {
  questionHooks.decorateWidget = decorate
  patchQuestions()
}

// Pending non-blocking questions take the editor's place as soon as nothing
// else holds it, like blocking ones, and esc cancels them rather than
// collapsing them back into the widget. The widget remains only while a
// dialog or another question is up.
export function expandPendingQuestions(): void {
  questionHooks.expandPending = true
  patchQuestions()
}

function decorateNew(host: QuestionHost, before: QuestionComponent | undefined): void {
  const question = host.askUserQuestion
  if (question && question !== before) questionHooks.decorate?.(question)
}

function expandPending(host: QuestionHost): void {
  if (!questionHooks.expandPending || host.askUserQuestion) return
  if (host.ui.hasOverlay() || host.extensionSelector || host.extensionInput || host.extensionEditor) return
  const shown = host.shownQuestionId
  const id = shown !== undefined && host.pendingQuestions.has(shown) ? shown : host.pendingOrder.find((i) => host.pendingQuestions.has(i))
  if (id !== undefined) host.expandPendingQuestion(id)
}

function patchQuestions(): void {
  patch(mode, "showQuestionOverlay", (original) =>
    function (this: QuestionHost, ...args: unknown[]) {
      const before = this.askUserQuestion
      const result = original.apply(this, args)
      decorateNew(this, before)
      return result
    },
  )
  // omo's expanded pending question hands a cancel back to the widget; when
  // pending questions take over the prompt, it finishes the question instead,
  // with the same cancelled response a blocking question resolves with.
  patch(mode, "expandPendingQuestion", (original) =>
    function (this: QuestionHost, requestId = this.shownQuestionId, ...rest: unknown[]) {
      const before = this.askUserQuestion
      const state = requestId === undefined ? undefined : this.pendingQuestions.get(requestId)
      const result = original.call(this, requestId, ...rest)
      const question = this.askUserQuestion
      if (questionHooks.expandPending && state && question && question !== before) {
        const done = question.doneCallback
        question.doneCallback = (response) => (response.status === "cancelled" ? state.finish(response) : done.call(question, response))
      }
      decorateNew(this, before)
      return result
    },
  )
  patch(mode, "refreshAsyncWidget", (original) =>
    function (this: QuestionHost, ...args: unknown[]) {
      // Shadow setExtensionWidget on the instance for this call only, so the
      // widget factory is wrapped while the prototype method (and any hook
      // on it, such as onWidget) still runs.
      const set = this.setExtensionWidget
      const decorate = questionHooks.decorateWidget
      this.setExtensionWidget = function (this: QuestionHost, key: string, factory?: WidgetFactory, ...rest: unknown[]) {
        const wrapped = key === "ask-user" && factory && decorate ? (...a: unknown[]) => decorate(factory(...a)) : factory
        return set.call(this, key, wrapped, ...rest)
      }
      try {
        return original.apply(this, args)
      } finally {
        delete (this as Partial<QuestionHost>).setExtensionWidget
        expandPending(this)
      }
    },
  )
  // A closed question (blocking or not) gives the editor back; the next
  // pending question takes it at once.
  patch(mode, "hideQuestionOverlay", (original) =>
    function (this: QuestionHost, ...args: unknown[]) {
      const result = original.apply(this, args)
      expandPending(this)
      return result
    },
  )
}

// Status above the prompt. omo draws its working, retry, compaction and
// branch-summary indicators (Loader subclasses, one at a time, kept on
// activeStatusIndicator) into statusContainer and each running tool hook into
// hookStatusContainer; compaction adds its indicator without going through
// showStatusIndicator, so the containers are hooked, not the methods that
// fill them. They are fields of the InteractiveMode instance, reached through
// renderWidgets, which omo runs whenever a widget is set (initHost sets one
// on every session start). The instance outlives /reload; patch() keeps the
// containers' own render under a symbol, so each copy of this module wraps it
// once. While anything is active the hook draws both containers as one block
// (the hook container then draws nothing); otherwise omo's render stands.
export type StatusSnapshot = {
  indicator?: { kind: string; message: string; elapsedSeconds?: number; progress?: string }
  hooks: { name: string; message?: string; elapsedSeconds: number }[]
  interruptKey: string
}
type StatusHost = {
  statusContainer: Component
  hookStatusContainer: Component
  pendingMessagesContainer: { clear(): void; addChild(component: Component): void }
  activeStatusIndicator?: { kind: string; message: string; progressText?: string }
  activeWorkingIndicatorEmbedded?: boolean
  activeToolHooks: Map<string, { hookName: string; statusMessage?: string; startedAt: number }>
  getWorkingElapsedSeconds(): number
  getAllQueuedMessages(): { steering: string[]; followUp: string[] }
  getAppKeyDisplay(action: string): string
  sessionManager: { getCwd(): string; getSessionName(): string | undefined }
}
type StatusHook = (status: StatusSnapshot, width: number) => string[]
let statusHook: StatusHook | undefined

export function onStatusLine(draw: StatusHook): void {
  statusHook = draw
  patch(mode, "renderWidgets", (original) =>
    function (this: StatusHost, ...args: unknown[]) {
      patchStatus(this)
      return original.apply(this, args)
    },
  )
}

function statusSnapshot(host: StatusHost): StatusSnapshot | undefined {
  const active = host.activeWorkingIndicatorEmbedded ? undefined : host.activeStatusIndicator
  const now = Date.now()
  const hooks = [...host.activeToolHooks.values()].map((h) => ({
    name: h.hookName,
    message: h.statusMessage || undefined,
    elapsedSeconds: Math.max(0, Math.floor((now - h.startedAt) / 1000)),
  }))
  if (!active && hooks.length === 0) return undefined
  const indicator = active && {
    kind: active.kind,
    message: active.message,
    elapsedSeconds: active.kind === "working" ? host.getWorkingElapsedSeconds() : undefined,
    progress: active.progressText || undefined,
  }
  return { indicator, hooks, interruptKey: host.getAppKeyDisplay("app.interrupt") }
}

function patchStatus(host: StatusHost): void {
  patch(host.statusContainer, "render", (original) =>
    function (this: Component, width: number) {
      const status = statusHook && statusSnapshot(host)
      return status ? statusHook!(status, width) : original.call(this, width)
    },
  )
  patch(host.hookStatusContainer, "render", (original) =>
    function (this: Component, width: number) {
      return statusHook ? [] : original.call(this, width)
    },
  )
}

// Queued steering and follow-up messages. omo rebuilds pendingMessagesContainer
// from its queues in updatePendingMessagesDisplay (and clears it first, as
// here); the hook returns the component drawn in its place.
export type QueuedMessages = { steering: string[]; followUp: string[]; dequeueKey: string }
let queueHook: ((queued: QueuedMessages) => Component) | undefined

export function onQueuedMessages(draw: (queued: QueuedMessages) => Component): void {
  queueHook = draw
  patch(mode, "updatePendingMessagesDisplay", (original) =>
    function (this: StatusHost, ...args: unknown[]) {
      if (!queueHook) return original.apply(this, args)
      this.pendingMessagesContainer.clear()
      const { steering, followUp } = this.getAllQueuedMessages()
      if (steering.length === 0 && followUp.length === 0) return
      this.pendingMessagesContainer.addChild(queueHook({ steering, followUp, dequeueKey: this.getAppKeyDisplay("app.message.dequeue") }))
    },
  )
}

// Terminal title when nothing more specific holds it: omo prefers a running
// tool or hook, then a pending question, then ctx.ui.setTitle, then this.
// ctx.ui.setTitle(undefined) re-applies it.
export function onTerminalTitle(make: (session: { name?: string; cwd: string }) => string): void {
  patch(mode, "getNormalTerminalTitle", () =>
    function (this: StatusHost) {
      return make({ name: this.sessionManager.getSessionName() || undefined, cwd: this.sessionManager.getCwd() })
    },
  )
}
