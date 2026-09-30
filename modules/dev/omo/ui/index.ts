// omo UI customisations, one file per surface, built on the shared core in
// ./core. omo.nix installs this directory as ~/.omo/agent/extensions/ui. To
// try an edit before rebuilding:
// omo -e ~/nix-config/modules/dev/omo/ui/index.ts
import type { ExtensionAPI } from "@code-yeongyu/senpi"
import backdrop from "./backdrop.ts"
import btw from "./btw.ts"
import code from "./code.ts"
import { stripChrome } from "./core/card.ts"
import { initHost, onSelectionText } from "./core/host.ts"
import { initStore } from "./core/store.ts"
import footer from "./footer.ts"
import prompt from "./prompt.ts"
import question from "./question.ts"
import sessions from "./sessions.ts"
import sidebar from "./sidebar.ts"
import tools from "./tools.ts"
import turn from "./turn.ts"

export default function (pi: ExtensionAPI) {
  initHost(pi)
  initStore(pi)
  prompt(pi)
  question(pi)
  footer(pi)
  turn(pi)
  tools(pi)
  sidebar(pi)
  sessions(pi)
  btw()
  backdrop()
  code(pi)
  onSelectionText(stripChrome)
}
