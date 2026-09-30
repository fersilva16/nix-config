// The one module that touches omo internals: anything the extension API does
// not cover (the fullscreen layout root, frame compositing, text selection,
// tool rows). Feature files call these helpers, so an omo upgrade that moves
// an internal breaks here and nowhere else.
import { ExtensionRunner, highlightCode, InteractiveMode, ToolExecutionComponent } from "@code-yeongyu/senpi"
import { Markdown, Spacer, Text, TuiAltScreen } from "@earendil-works/pi-tui"
import type { Component, Theme, Tui } from "./types.ts"
import {
  AssistantMessageComponent,
  BashExecutionComponent,
  BranchSummaryMessageComponent,
  CompactionSummaryMessageComponent,
  SkillInvocationMessageComponent,
  UserMessageComponent,
} from "@code-yeongyu/senpi"
import { Text } from "@earendil-works/pi-tui"
import { stripAnsi } from "./style.ts"

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
  const overlay = host.ui.showOverlay(ownOverlay(shown.component), { width, anchor: "center" })
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

// Stock overlays: every tui.showOverlay call (ctx.ui.custom overlays such as
// /help, /history, /diff and /files, and the fullscreen transcript search the
// alt-screen tui opens on itself). Our own modals are marked and pass through.
// The hook may return a component (and options) to show instead; it should
// forward input and focus to the stock one, which keeps its keys and result.
// `help` is omo's HelpPanel, which sizes its scroll viewport to the terminal:
// `reserveRows` shrinks that viewport by the rows the replacement adds.
// `search` is the transcript search bar, whose mouse hit-test reads rows and
// columns of the stock layout, so a replacement must keep that geometry.
const OWN_OVERLAY = Symbol.for("omo-ui.overlay.own")
export type StockOverlay = { kind: "help" | "search" | "panel"; component: Component; options: Record<string, unknown> | undefined }
type OverlayHook = (overlay: StockOverlay, tui: Tui) => { component: Component; options?: Record<string, unknown>; reserveRows?: number } | undefined
type HelpShape = Component & { viewportHeight?: () => number; maxOffset?: () => number }

export function ownOverlay<C extends object>(component: C): C {
  return Object.assign(component, { [OWN_OVERLAY]: true })
}

let overlayHook: OverlayHook | undefined

export function onOverlay(hook: OverlayHook): void {
  overlayHook = hook
  onTui((t) =>
    patch(t, "showOverlay", (original) =>
      function (this: HostTui, component: Component & { [OWN_OVERLAY]?: boolean }, options?: Record<string, unknown>) {
        if (component[OWN_OVERLAY] || options?.nonCapturing || !overlayHook) return original.call(this, component, options)
        const c = component as HelpShape & { getNavigationDirectionAt?: unknown }
        const kind = typeof c.getNavigationDirectionAt === "function" ? "search" : typeof c.viewportHeight === "function" && typeof c.maxOffset === "function" ? "help" : "panel"
        const shown = overlayHook({ kind, component, options }, this)
        if (!shown) return original.call(this, component, options)
        if (kind === "help" && shown.reserveRows) {
          const viewport = c.viewportHeight!.bind(c)
          const reserve = shown.reserveRows
          c.viewportHeight = () => Math.max(1, viewport() - reserve)
        }
        return original.call(this, shown.component, shown.options ?? options)
      },
    ),
  )
  patchCustom()
}

// ctx.ui.custom without `overlay` (omo's /diff and /files) puts the
// component in the editor's place. When the hook takes it, it is shown as
// an overlay instead and the editor's place gets a stand-in that draws the
// editor and hands keys to omo's component; closing hides the overlay.
// The settings takeover (/llama) also watches the editor container here and
// gets first claim on the component: patch() wraps omo's original,
// so onOverlay and onTakeover must share this one wrapper.
function patchCustom(): void {
  patch(mode, "showExtensionCustom", (original) =>
    function (this: { ui: HostTui & { showOverlay(c: Component, o?: unknown): Overlay }; editor: Component }, factory: CustomFactory, options?: { overlay?: boolean }) {
      if (takeoverHook) watchEditorContainer(this as unknown as TakeoverHost)
      if (options?.overlay || !overlayHook) return original.call(this, factory, options)
      const host = this
      let overlay: Overlay | undefined
      const wrapped: CustomFactory = (t, theme, keys, done) => {
        const close = (value: unknown) => {
          overlay?.hide()
          overlay = undefined
          done(value)
        }
        return Promise.resolve(factory(t, theme, keys, close)).then((c) => {
          const claimed = c && takeoverHook?.({ name: c.constructor?.name ?? "", stock: c }, host.ui as unknown as Tui)
          const shown = c && !claimed && overlayHook?.({ kind: "panel", component: c, options: undefined }, host.ui)
          if (!shown) return c
          overlay = host.ui.showOverlay(ownOverlay(shown.component), shown.options)
          const stock = c as Component & { dispose?(): void }
          return {
            render: (width: number) => host.editor.render(width),
            invalidate: () => stock.invalidate(),
            handleInput: (data: string) => stock.handleInput?.(data),
            dispose: () => stock.dispose?.(),
          }
        })
      }
      return original.call(this, wrapped, options)
    },
  )
}
type CustomFactory = (tui: unknown, theme: unknown, keys: unknown, done: (value: unknown) => void) => Component | Promise<Component>

// Commands omo answers by appending text to the transcript: /hotkeys,
// /session and /changelog. While one runs, the text, spacer, markdown and
// border components it appends are held back; the hook gets a render of them
// and returns true to take them (omo's copy is then never added). Anything
// else appended meanwhile (a streaming reply during /session's await) passes
// through untouched.
export type TranscriptPanel = "hotkeys" | "session" | "changelog"
type PanelHook = (panel: TranscriptPanel, render: (width: number) => string[]) => boolean
type ChatHost = { chatContainer: { addChild(component: Component): void } }
const PANEL_METHODS: Record<TranscriptPanel, string> = {
  hotkeys: "handleHotkeysCommand",
  session: "handleSessionCommand",
  changelog: "handleChangelogCommand",
}

let panelHook: PanelHook | undefined

const isPanelPart = (c: Component) => c instanceof Text || c instanceof Spacer || c instanceof Markdown || c.constructor?.name === "DynamicBorder"

export function onTranscriptPanel(hook: PanelHook): void {
  panelHook = hook
  for (const [panel, name] of Object.entries(PANEL_METHODS) as [TranscriptPanel, string][]) {
    patch(mode, name, (original) =>
      function (this: ChatHost, ...args: unknown[]) {
        const chat = this.chatContainer
        const add = chat.addChild
        const held: Component[] = []
        // Shadowed on the instance for this call; deleting it restores the
        // prototype's addChild.
        chat.addChild = (c: Component) => (isPanelPart(c) ? void held.push(c) : add.call(chat, c))
        const finish = () => {
          delete (chat as Partial<ChatHost["chatContainer"]>).addChild
          const render = (width: number) => held.flatMap((c) => c.render(width))
          if (held.length > 0 && !panelHook?.(panel, render)) for (const c of held) add.call(chat, c)
        }
        let result: unknown
        try {
          result = original.apply(this, args)
        } catch (error) {
          finish()
          throw error
        }
        if (result instanceof Promise) return result.finally(finish)
        finish()
        return result
      },
    )
  }
}

// The "?" shortcut hint omo shows when "?" is typed into an empty editor.
// omo adds it to the header container, which in fullscreen is the top of the
// transcript and scrolled out of view in any real session. The hook gets a
// render of omo's lines and returns what to show instead as a non-capturing
// overlay (the editor keeps its keys); it closes when omo hides the hint, on
// the next edit.
const SHORTCUT_OVERLAY = Symbol.for("omo-ui.shortcut-overlay.handle")
type ShortcutHook = (render: (width: number) => string[]) => { component: Component; options: Record<string, unknown> } | undefined
type ShortcutHost = {
  shortcutOverlay?: Component
  headerContainer: { removeChild(component: Component): void }
  ui: { showOverlay(component: Component, options: Record<string, unknown>): Overlay }
  [SHORTCUT_OVERLAY]?: Overlay
}
let shortcutHook: ShortcutHook | undefined

export function onShortcutOverlay(hook: ShortcutHook): void {
  shortcutHook = hook
  patch(mode, "updateShortcutOverlay", (original) =>
    function (this: ShortcutHost, ...args: unknown[]) {
      const before = this.shortcutOverlay
      const result = original.apply(this, args)
      const hint = this.shortcutOverlay
      const shown = hint && hint !== before ? shortcutHook?.(hint.render.bind(hint)) : undefined
      if (hint && shown) {
        this.headerContainer.removeChild(hint)
        this[SHORTCUT_OVERLAY] = this.ui.showOverlay(ownOverlay(shown.component), { ...shown.options, nonCapturing: true })
      }
      return result
    },
  )
  patch(mode, "hideShortcutOverlay", (original) =>
    function (this: ShortcutHost, ...args: unknown[]) {
      this[SHORTCUT_OVERLAY]?.hide()
      delete this[SHORTCUT_OVERLAY]
      return original.apply(this, args)
    },
  )
}

// Screens omo puts in the editor's place: /settings, /trust, /login and
// /logout (their pickers, the login dialog and its prompts) and /llama.
// Some go through showSelector, some add themselves to the editor container
// directly, and the login dialog is re-added after each auth prompt, so the
// hook watches the container itself: every component added to it (other
// than the editor and extension dialogs, which onDialog owns) is offered to
// the hook, which may return a component drawn in its place as a centred
// overlay. omo focuses the screen, or a part of it (/settings focuses its
// list), right after adding it; that component becomes the takeover's
// `target`, which the overlay forwards keys to. omo's own clear() of the container,
// which every one of these screens ends with, closes the overlay and
// disposes the screen as it would have. The container is patched the first
// time one of the screens opens.
type Focusable = Component & { focused?: boolean }
export type Takeover = { name: string; stock: Focusable & { dispose?(): void }; target?: Focusable }
type TakeoverHook = (takeover: Takeover, tui: Tui) => { component: Component; width: number } | undefined
type TakeoverOverlay = Overlay & { focus(): void }
type TakeoverHost = DialogHost & { [TAKEOVER]?: { overlay: TakeoverOverlay; stock: Takeover["stock"] } }
const TAKEOVER = Symbol.for("omo-ui.takeover.overlay")
const TAKEOVER_ENTRIES = [
  "showSettingsSelector",
  "showTrustSelector",
  "showLoginAuthTypeSelector",
  "showLoginProviderSelector",
  "showOAuthSelector",
  "showLoginDialog",
  "showApiKeyLoginDialog",
  "showAmbientAuthDialog",
  "showAuthSelect",
]
let takeoverHook: TakeoverHook | undefined

export function onTakeover(present: TakeoverHook): void {
  takeoverHook = present
  for (const name of TAKEOVER_ENTRIES) {
    patch(mode, name, (original) =>
      function (this: TakeoverHost, ...args: unknown[]) {
        watchEditorContainer(this)
        return original.apply(this, args)
      },
    )
  }
  patchCustom()
}

function closeTakeover(host: TakeoverHost): void {
  const open = host[TAKEOVER]
  if (!open) return
  delete host[TAKEOVER]
  open.overlay.hide()
  open.stock.dispose?.()
}

function watchEditorContainer(host: TakeoverHost): void {
  const box = host.editorContainer as object
  patch(box, "addChild", (original) =>
    function (this: unknown, component: Takeover["stock"]) {
      if (component === host.editor || component === host.extensionSelector) return original.call(this, component)
      const takeover: Takeover = { name: component?.constructor?.name ?? "", stock: component }
      const shown = takeoverHook?.(takeover, host.ui)
      if (!shown) return original.call(this, component)
      closeTakeover(host)
      original.call(this, host.editor)
      const width = Math.min(shown.width, host.ui.terminal.columns - 4)
      const overlay = host.ui.showOverlay(ownOverlay(shown.component), { width, anchor: "center" }) as TakeoverOverlay
      host[TAKEOVER] = { overlay, stock: component }
      queueMicrotask(() => {
        if (host[TAKEOVER]?.overlay !== overlay) return
        const focused = (host.ui as { focusedComponent?: Focusable }).focusedComponent
        if (focused && focused !== shown.component) takeover.target = focused
        overlay.focus()
      })
    },
  )
  patch(box, "clear", (original) =>
    function (this: unknown) {
      closeTakeover(host)
      return original.call(this)
    },
  )
}

// Transcript entries omo draws with its own components, outside the
// renderer API: user messages (also the pending echo shown before the
// session accepts one), `!cmd` runs, compaction and branch summaries and
// skill invocations. Each class is exported, so its prototype's render is
// wrapped; the hook gets omo's content and draws the frame around it. For a
// `!cmd` run the content is the command, output and status without omo's
// border rules.
export type TranscriptEntry =
  | { kind: "user" | "compaction" | "branch" | "skill" }
  | { kind: "bash"; status: "running" | "complete" | "error" | "cancelled" }
type EntryHook = (entry: TranscriptEntry, render: (width: number) => string[], width: number) => string[]
type BashInternals = { status: "running" | "complete" | "error" | "cancelled"; contentContainer: Component }

let entryHook: EntryHook | undefined

export function onTranscriptEntry(hook: EntryHook): void {
  entryHook = hook
  const route = (proto: object, entry: (self: never) => TranscriptEntry, content?: (self: never, width: number) => string[]) =>
    patch(proto, "render", (original) =>
      function (this: never, width: number) {
        if (!entryHook) return original.call(this, width)
        return entryHook(entry(this), (w) => (content ? content(this, w) : original.call(this, w)), width)
      },
    )
  route(UserMessageComponent.prototype, () => ({ kind: "user" }))
  route(CompactionSummaryMessageComponent.prototype, () => ({ kind: "compaction" }))
  route(BranchSummaryMessageComponent.prototype, () => ({ kind: "branch" }))
  route(SkillInvocationMessageComponent.prototype, () => ({ kind: "skill" }))
  route(
    BashExecutionComponent.prototype,
    (self: BashInternals) => ({ kind: "bash", status: self.status }),
    (self: BashInternals, w) => self.contentContainer.render(w),
  )
}

// Thinking blocks. AssistantMessageComponent builds one child per part of
// the message; a thinking run is a label ("Thought: 3s", or the hidden
// label ctrl+t leaves) and, when shown, its markdown body. The child keeps
// omo's click-to-toggle handler, so its render is replaced in place.
type ThinkingBlockHook = (part: "label" | "body", render: (width: number) => string[], width: number) => string[]
let thinkingBlockHook: ThinkingBlockHook | undefined

export function onThinkingBlock(hook: ThinkingBlockHook): void {
  thinkingBlockHook = hook
  patch(AssistantMessageComponent.prototype as object, "createRenderChild", (original) =>
    function (this: unknown, descriptor: { kind: string }) {
      const child: Component = original.call(this, descriptor)
      const part = descriptor.kind === "thinking-label" ? "label" : descriptor.kind === "thinking-md" ? "body" : undefined
      if (!part) return child
      const render = child.render.bind(child)
      child.render = (width) => (thinkingBlockHook ? thinkingBlockHook(part, render, width) : render(width))
      return child
    },
  )
}

// Inline transcript notices: turn errors (showError; network errors go to
// omo's own provider-error block and never reach the hook), cache-miss and
// compaction-cost notices, session-continuity notices, assistant diagnostics
// and the untrusted-project warning. Each InteractiveMode method appends a
// plain Text to the transcript; while it runs, that Text goes through the
// hook, whose component (undefined keeps omo's) is added instead.
export type TranscriptNotice = { tone: "error" | "warning" | "muted"; text: string }
const NOTICE_METHODS: Record<string, TranscriptNotice["tone"]> = {
  showError: "error",
  addCacheMissNotice: "warning",
  addCompactionCostNotice: "warning",
  addContinuityNotice: "muted",
  maybeShowAssistantDiagnostics: "warning",
  renderProjectTrustWarningIfNeeded: "warning",
}
type NoticeHook = (notice: TranscriptNotice) => Component | undefined
type ChatHost = { chatContainer: { addChild(component: Component): void } }
let noticeHook: NoticeHook | undefined

export function onTranscriptNotice(hook: NoticeHook): void {
  noticeHook = hook
  for (const [name, tone] of Object.entries(NOTICE_METHODS))
    patch(mode, name, (original) =>
      function (this: ChatHost, ...args: unknown[]) {
        // Shadowed on the instance for this call only, like refreshAsyncWidget.
        const chat = this.chatContainer
        const add = chat.addChild
        chat.addChild = function (this: unknown, component: Component) {
          const text = component instanceof Text ? stripAnsi((component as Component & { text: string }).text) : undefined
          const notice = text && { tone, text: tone === "error" ? text.replace(/^Error: /, "") : text }
          return add.call(this, (notice && noticeHook?.(notice)) || component)
        }
        try {
          return original.apply(this, args)
        } finally {
          delete (chat as Partial<ChatHost["chatContainer"]>).addChild
        }
      },
    )
}
