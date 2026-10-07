// /ship [merge]: a command, not a prompt template, so it can gather the repo
// state before the turn and the agent spends no tool calls finding it.
import { execFile } from "node:child_process"
import { readFileSync } from "node:fs"
import { promisify } from "node:util"
import type { ExtensionAPI } from "@code-yeongyu/senpi"

const exec = promisify(execFile)
const instructions = readFileSync(new URL("./ship.md", import.meta.url), "utf8")

// A failing command (no remote, not GitHub) shows its error instead.
const discovery: [label: string, cmd: string, args: string[]][] = [
  ["git status", "git", ["status", "--short", "--branch"]],
  ["Default branch", "gh", ["repo", "view", "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"]],
  // Not `gh pr view`: it exits 1 when the branch has no PR.
  ["PR for this branch", "gh", ["pr", "status", "--json", "url,state", "--jq", '.currentBranch // "none"']],
  ["Recent commits", "git", ["log", "--oneline", "-5"]],
]

export default function (pi: ExtensionAPI) {
  pi.registerCommand("ship", {
    description: "Commit, push and open a PR (merge: also merge it)",
    getArgumentCompletions: (prefix) => ("merge".startsWith(prefix) ? [{ value: "merge", label: "merge" }] : null),
    handler: async (args, ctx) => {
      await ctx.waitForIdle()
      const results = await Promise.allSettled(discovery.map(([, cmd, argv]) => exec(cmd, argv, { cwd: ctx.cwd })))
      const state = results.map((r, i) => {
        const out = r.status === "fulfilled" ? r.value.stdout : `failed: ${(r.reason.stderr || r.reason.message)}`
        return `### ${discovery[i][0]}\n\`\`\`\n${out.trim()}\n\`\`\``
      })
      pi.sendUserMessage(`${instructions}\nArguments: ${args.trim() || "(none)"}\n\n${state.join("\n")}\n`)
    },
  })
}
