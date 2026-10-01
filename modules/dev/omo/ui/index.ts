// omo UI customisations, one file per surface, built on the shared core in
// ./core. omo.nix installs this directory as ~/.omo/agent/extensions/ui. To
// try an edit before rebuilding:
// omo -e ~/nix-config/modules/dev/omo/ui/index.ts
import type { ExtensionAPI } from "@code-yeongyu/senpi"
import backdrop from "./backdrop.ts"
import btw from "./btw.ts"
import code from "./code.ts"
import { stripChrome } from "./core/card.ts"
import cursor from "./cursor.ts"
import { initHost, onSelectionText } from "./core/host.ts"
import { initStore } from "./core/store.ts"
import dialogs from "./dialogs.ts"
import entries from "./entries.ts"
import footer from "./footer.ts"
import navigation from "./navigation.ts"
import panels from "./panels.ts"
import pickers from "./pickers.ts"
import prompt from "./prompt.ts"
import question from "./question.ts"
import settings from "./settings.ts"
import sidebar from "./sidebar.ts"
import status from "./status.ts"
import tools from "./tools.ts"
import transcript from "./transcript.ts"
import turn from "./turn.ts"
import widgets from "./widgets.ts"

export default function (pi: ExtensionAPI) {
  initHost(pi)
  initStore(pi)
  prompt(pi)
  cursor(pi)
  question(pi)
  footer(pi)
  status(pi)
  turn(pi)
  tools(pi)
  sidebar(pi)
  navigation()
  btw()
  dialogs(pi)
  pickers()
  panels(pi)
  settings()
  backdrop()
  code(pi)
  entries()
  widgets()
  transcript(pi)
  onSelectionText(stripChrome)
}
