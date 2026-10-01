// A blinking bar cursor in the editor. omo shows the terminal's own cursor
// there (showHardwareCursor, set in omo.nix) but never picks its shape, and
// under tmux a pane with no shape set gets the terminfo reset, which for
// xterm-ghostty is a steady block (Se=\E[2 q). So ask for the bar (DECSCUSR 5)
// once the tui is up, and hand the default back on exit.
import { onTui } from "./core/host.ts"
import type { Tui } from "./core/types.ts"

type Pi = { on(event: "session_shutdown", handler: () => void): void }

export default function cursor(pi: Pi) {
  let tui: Tui | undefined
  // Only where a tui is mounted: the RPC host's stdout is its protocol.
  onTui((t) => {
    tui = t
    t.terminal.write("\x1b[5 q")
  })
  pi.on("session_shutdown", () => tui?.terminal.write("\x1b[0 q"))
}
