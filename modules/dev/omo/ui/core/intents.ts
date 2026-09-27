// Prompt key bindings as data. The custom editor sees keys before omo's app
// bindings, so a Keymap in its handleInput can add chords omo lacks: a leader
// key (opencode's ctrl+x) followed by one key, or a plain key gated by `when`.
import { Key, matchesKey } from "@earendil-works/pi-tui"

export type Intent<E> = {
  // A single character matches itself; anything else is a pi-tui key id
  // such as "tab" or "ctrl+o".
  key: string
  leader?: boolean
  when?: (editor: E) => boolean
  // `leaderData` is the raw leader key press, for intents that replay it.
  run(editor: E, data: string, leaderData?: string): void
}

const hits = (data: string, key: string) => (key.length === 1 ? data === key : matchesKey(data, key))

export class Keymap<E> {
  private pending: string | undefined

  constructor(
    private readonly leader: string,
    private readonly intents: Intent<E>[],
  ) {}

  // Esc after the leader cancels it; any other unbound key is typed as usual.
  handle(editor: E, data: string, fallback: (data: string) => void): void {
    const pending = this.pending
    this.pending = undefined
    if (pending !== undefined) {
      const intent = this.intents.find((i) => i.leader && hits(data, i.key))
      if (intent) return intent.run(editor, data, pending)
      if (matchesKey(data, Key.escape)) return
      return fallback(data)
    }
    if (matchesKey(data, this.leader)) {
      this.pending = data
      return
    }
    const intent = this.intents.find((i) => !i.leader && hits(data, i.key) && (i.when?.(editor) ?? true))
    if (intent) return intent.run(editor, data)
    fallback(data)
  }
}

type Submitting = { getText(): string; setText(text: string): void; onSubmit?: (text: string) => void }

// Runs a slash command as if typed. Command handlers need the command
// context, which only a submitted command gets, and omo's submit handler reads
// the editor text rather than its argument, so the draft is swapped out and
// restored around it.
export function submitCommand(editor: Submitting, command: string): void {
  const draft = editor.getText()
  editor.setText(command)
  editor.onSubmit?.(command)
  editor.setText(draft)
}
