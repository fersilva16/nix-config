// omo UI customisations, one file per surface. omo.nix installs this
// directory as ~/.omo/agent/extensions/ui. To try an edit before rebuilding:
// omo -e ~/nix-config/modules/dev/omo/ui/index.ts
import type { ExtensionAPI } from "@code-yeongyu/senpi"
import footer from "./footer.ts"
import prompt from "./prompt.ts"
import sidebar from "./sidebar.ts"
import tools from "./tools.ts"
import turn from "./turn.ts"

export default function (pi: ExtensionAPI) {
  prompt(pi)
  footer(pi)
  turn(pi)
  tools(pi)
  sidebar(pi)
}
