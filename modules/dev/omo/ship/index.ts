// /ship [merge]: commit all local changes as one conventional commit, push and
// open a PR; `merge` also squash-merges it. A prompt template can't run shell,
// so this is a command: it gathers the repo state before the turn starts (the
// agent spends no tool calls finding it) and sends ship.md with it appended.
import { execFile } from "node:child_process"
import { readFileSync } from "node:fs"
import { promisify } from "node:util"
import type { ExtensionAPI } from "@code-yeongyu/senpi"

const exec = promisify(execFile)
const instructions = readFileSync(new URL("./ship.md", import.meta.url), "utf8")

// Run from the repo root; any non-zero exit aborts /ship before the turn.
const discovery: [label: string, cmd: string, args: string[]][] = [
  ["Branch (empty = detached HEAD)", "git", ["branch", "--show-current"]],
  ["Default branch", "gh", ["repo", "view", "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"]],
  // Not `gh pr view`: it exits 1 when the branch has no PR.
  ["PR for this branch", "gh", ["pr", "status", "--json", "number,url,state,baseRefName,title", "--jq", '.currentBranch // "none"']],
  ["Recent commits (match their style)", "git", ["log", "--oneline", "-8"]],
  ["Status (.omo/ excluded)", "git", ["status", "--short", "--branch", "--", ".", ":(exclude,glob)**/.omo/**"]],
  ["Diffstat vs HEAD (untracked files appear only in the status)", "git", ["diff", "--stat", "HEAD"]],
]

export default function (pi: ExtensionAPI) {
  pi.registerCommand("ship", {
    description: "Commit all local changes as one commit, push, open a PR (merge: also squash-merge)",
    getArgumentCompletions: (prefix) => ("merge".startsWith(prefix) ? [{ value: "merge", label: "merge" }] : null),
    handler: async (args, ctx) => {
      await ctx.waitForIdle()

      let root: string
      try {
        root = (await exec("git", ["rev-parse", "--show-toplevel"], { cwd: ctx.cwd })).stdout.trim()
      } catch {
        ctx.ui.notify("/ship: not inside a git repository", "error")
        return
      }

      const results = await Promise.allSettled(discovery.map(([, cmd, argv]) => exec(cmd, argv, { cwd: root })))
      const outputs: string[] = []
      for (const [i, result] of results.entries()) {
        if (result.status === "rejected") {
          const [, cmd, argv] = discovery[i]
          const err = result.reason as { stderr?: string; message: string }
          ctx.ui.notify(`/ship: \`${cmd} ${argv.join(" ")}\` failed: ${(err.stderr || err.message).trim()}`, "error")
          return
        }
        outputs.push(result.value.stdout.trim())
      }

      // Clean tree, tracking an upstream, nothing unpushed: no turn needed.
      const status = outputs[4].split("\n")
      if (status.length === 1 && status[0].includes("...") && !status[0].includes("[ahead")) {
        ctx.ui.notify("/ship: nothing to ship (clean tree, nothing unpushed)", "info")
        return
      }

      const state = discovery
        .map(([label], i) => `### ${label}\n\n\`\`\`\n${outputs[i] || "(empty)"}\n\`\`\``)
        .join("\n\n")
      pi.sendUserMessage(
        `${instructions}\n## Current state\n\nRepo root: ${root}\nArguments: ${args.trim() || "(none)"}\n\n${state}\n`,
      )
    },
  })
}
