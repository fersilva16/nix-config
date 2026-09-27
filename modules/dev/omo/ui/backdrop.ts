// opencode-style modal backdrop. Terminals have no translucency, so while any
// capturing overlay is open the frame under it is repainted flat: every cell
// keeps its text but loses its colours to one dark fg/bg pair, which pushes
// the transcript back and makes the dialog the only thing that reads. While a
// frame is faded, sidebar.ts skips its per-row colour reset, which would
// otherwise cut the fade off at the transcript edge.
import { visibleWidth } from "@earendil-works/pi-tui"
import { beforeOverlays, onTui } from "./core/host.ts"
import { stripAnsi } from "./core/style.ts"

// opencode's black-at-~60% scrim over Flexoki paper; the text under it is
// only a faint ghost (base600), so nothing behind the dialog competes with it.
const BG = "\x1b[48;2;94;93;89m"
const FG = "\x1b[38;2;111;110;105m"

function fade(screen: string[], width: number): string[] {
  return screen.map((line) => {
    const text = stripAnsi(line)
    return `${BG}${FG}${text}${" ".repeat(Math.max(0, width - visibleWidth(text)))}\x1b[0m`
  })
}

export default function backdrop() {
  onTui((tui) => beforeOverlays(tui, (screen, width, modal) => (modal ? fade(screen, width) : screen)))
}
