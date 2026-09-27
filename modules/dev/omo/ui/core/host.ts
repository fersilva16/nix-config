// The one module that touches omo internals: anything the extension API does
// not cover (the fullscreen layout root, frame compositing, text selection,
// tool rows). Feature files call these helpers, so an omo upgrade that moves
// an internal breaks here and nowhere else.
import { highlightCode, InteractiveMode, ToolExecutionComponent } from "@code-yeongyu/senpi"
import { Markdown, TuiAltScreen } from "@earendil-works/pi-tui"
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
  patch(mode, "setExtensionWidget", (original) =>
    function (this: unknown, k: string, content: unknown, options: unknown) {
      return original.call(this, k, k === key && take() ? undefined : content, options)
    },
  )
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
