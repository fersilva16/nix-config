// Registers the Framelink Figma MCP server with omo. The API key stays in
// ~/.config/figma/.env, which the server reads itself at spawn.
import { homedir } from "node:os"
import { join } from "node:path"

export default function (pi: { registerMcpServer(name: string, config: object): void }) {
  pi.registerMcpServer("figma", {
    command: "@figmaMcp@",
    args: ["--stdio", "--env", join(homedir(), ".config/figma/.env")],
  })
}
