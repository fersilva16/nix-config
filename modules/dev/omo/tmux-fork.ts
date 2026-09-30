// /fork into a new, focused tmux window; this pane stays on the original. /clone
// is left alone. Extensions can't replace built-in commands, so this cancels the
// native fork and redoes it out of process.
//
// The cut goes through a throwaway forkFrom copy: createBranchedSession deletes
// the blobs dir of the file it was opened on, so it must never touch the live one.
// It also records that copy as parentSession, so the header is repointed at the
// original to keep the fork nested under it in the session list.
import { spawnSync } from "node:child_process"
import { readFileSync, rmSync, writeFileSync } from "node:fs"
import { SessionManager, type ExtensionAPI } from "@code-yeongyu/senpi"

const EDITOR_ENV = "OMO_TMUX_FORK_EDITOR"

function textOf(content: unknown): string {
  if (typeof content === "string") return content
  if (!Array.isArray(content)) return ""
  return content.map((p: { text?: unknown }) => (typeof p?.text === "string" ? p.text : "")).join("")
}

export default function (pi: ExtensionAPI) {
  const pane = process.env.TMUX_PANE
  if (pi.sessionKind !== "interactive" || !pane) return

  pi.on("session_start", (_event, ctx) => {
    const text = process.env[EDITOR_ENV]
    if (text === undefined) return
    delete process.env[EDITOR_ENV]
    ctx.ui.setEditorText(text)
  })

  pi.on("session_before_fork", (event, ctx) => {
    const original = ctx.sessionManager.getSessionFile()
    const entry = ctx.sessionManager.getEntry(event.entryId)
    if (event.position !== "before" || !original || !entry) return

    let forked: string | undefined
    if (entry.parentId) {
      const copy = SessionManager.forkFrom(original, ctx.cwd, ctx.sessionManager.getSessionDir())
      const copyFile = copy.getSessionFile()
      forked = copy.createBranchedSession(entry.parentId)
      if (copyFile) rmSync(copyFile, { force: true })
    }
    if (forked) {
      const [header, ...rest] = readFileSync(forked, "utf8").split("\n")
      writeFileSync(forked, [JSON.stringify({ ...JSON.parse(header), parentSession: original }), ...rest].join("\n"))
    }

    const window = spawnSync("tmux", ["display-message", "-p", "-t", pane, "#{window_id}"], { encoding: "utf8" }).stdout.trim()
    const text = entry.type === "message" ? textOf(entry.message.content) : ""
    const res = spawnSync(
      "tmux",
      ["new-window", "-a", "-t", window, "-c", ctx.cwd, "-e", `${EDITOR_ENV}=${text}`, "omo", ...(forked ? ["--session", forked] : [])],
      { encoding: "utf8" },
    )
    if (res.status !== 0) {
      ctx.ui.notify(`tmux new-window failed: ${res.stderr || res.error}`, "error")
      return
    }
    return { cancel: true }
  })
}
