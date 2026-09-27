// omo ships no type declarations for its extension API, so these are the
// structural subsets of its objects that this extension reads.
export type Theme = {
  fg(token: string, text: string): string
  bg(token: string, text: string): string
  bold(text: string): string
}

export type Component = {
  render(width: number): string[]
  invalidate(): void
  handleInput?(data: string): void
  handleMouse?(event: { x: number; y: number; width: number }): unknown
}

export type Tui = {
  requestRender(): void
  terminal: { rows: number; columns: number }
}

type Usage = { cost?: { total?: number } }
export type Block = { type: string; id?: string; text?: string; name?: string; arguments?: { path?: string } }
export type Entry = {
  type: string
  message?: { role?: string; content?: Block[] | string; usage?: Usage }
}

export type Ctx = {
  cwd: string
  model?: { id: string; name?: string; provider?: string }
  getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined
  sessionManager: { getBranch(): Entry[]; getSessionId(): string }
}
