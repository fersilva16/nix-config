// /wt [name] [branch]: move this session into a worktree, the omo side of the
// `wt` fish function. `wt` itself makes the worktree and its tmux session (new
// or existing); this forks the conversation into the worktree's cwd, opens it
// there in a new window, switches to it and kills the window it came from.
//
// The move is a forkFrom + delete rather than a rename: omo files sessions
// under a directory derived from their cwd, and forkFrom is its own way of
// re-homing one. The original is deleted only once this process has exited,
// so nothing can append to it after the copy was taken.
import { execFile, execFileSync, spawnSync } from "node:child_process"
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs"
import { basename, dirname, join } from "node:path"
import { promisify } from "node:util"
import { SessionManager, type ExtensionAPI } from "@code-yeongyu/senpi"

const run = promisify(execFile)
const NEW = "+ new worktree"

const tmux = (...args: string[]) => spawnSync("tmux", args, { encoding: "utf8" })
const quote = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`

// Same layout `wt` uses: <main_root>.worktrees/<name> beside the main checkout.
function worktreesDir(cwd: string): string | undefined {
  try {
    const first = execFileSync("git", ["-C", cwd, "worktree", "list", "--porcelain"], { encoding: "utf8" }).split("\n")[0]
    const main = first.replace(/^worktree /, "")
    return join(dirname(main), `${basename(main)}.worktrees`)
  } catch {
    return undefined
  }
}

function worktrees(dir: string): string[] {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isDirectory() && !e.name.startsWith("."))
      .map((e) => e.name)
  } catch {
    return []
  }
}

export default function (pi: ExtensionAPI) {
  const pane = process.env.TMUX_PANE
  if (pi.sessionKind !== "interactive" || !pane) return

  pi.registerCommand("wt", {
    description: "Move this session into a worktree (new or existing), like `wt`",
    getArgumentCompletions: (prefix) => {
      if (prefix.includes(" ")) return null
      const dir = worktreesDir(pi.cwd)
      const items = (dir ? worktrees(dir) : []).filter((n) => n.startsWith(prefix)).map((n) => ({ value: n, label: n }))
      return items.length > 0 ? items : null
    },
    handler: async (args, ctx) => {
      const dir = worktreesDir(ctx.cwd)
      if (!dir) return ctx.ui.notify("wt: not a git repo", "error")

      let [name, branch] = args.trim().split(/\s+/).filter(Boolean)
      if (!name) {
        const pick = await ctx.ui.select("Move session to worktree:", [NEW, ...worktrees(dir)])
        if (!pick) return
        name = pick === NEW ? (await ctx.ui.input("New worktree name:"))?.trim() ?? "" : pick
        if (!name) return
      }
      const wtPath = join(dir, name)
      if (wtPath === ctx.cwd) return ctx.ui.notify(`wt: already in worktree '${name}'`, "warning")

      // Don't copy a conversation that is still being written.
      await ctx.waitForIdle()

      // A session with no reply yet has no file; there is nothing to carry.
      // Forked up front so the omo command is known before wt starts the
      // session; forkFrom only needs the target path, not the directory.
      const original = ctx.sessionManager.getSessionFile()
      let moved: string | undefined
      if (original && existsSync(original)) {
        moved = SessionManager.forkFrom(original, wtPath).getSessionFile()
        if (!moved) return ctx.ui.notify("wt: could not copy the session", "error")
        // The original is about to be deleted, so it can't be the parent.
        const [header, ...rest] = readFileSync(moved, "utf8").split("\n")
        const { parentSession: _, ...h } = JSON.parse(header)
        writeFileSync(moved, [JSON.stringify({ ...h, cwd: wtPath }), ...rest].join("\n"))
      }
      const omo = ["omo", ...(moved ? ["--session", moved] : [])]

      const parent = tmux("display-message", "-p", "-t", pane, "#{session_name}").stdout.trim().split("/")[0]
      const session = `${parent}/${name}`
      const oldWindow = tmux("display-message", "-p", "-t", pane, "#{window_id}").stdout.trim()
      const sessionExists = tmux("has-session", "-t", `=${session}`).status === 0

      // WT_SYNC: the checkout must exist before omo starts in it. WT_DETACH:
      // switch only once omo is up, so you never see wt's shell. WT_EXEC: when
      // wt makes the session, omo is its first window rather than a second.
      ctx.ui.setStatus("wt", `wt: preparing ${name}…`)
      let failure = ""
      try {
        await run("fish", ["-c", "wt $argv", "--", name, ...(branch ? [branch] : [])], {
          cwd: ctx.cwd,
          env: {
            ...process.env,
            WT_SYNC: "1",
            WT_DETACH: "1",
            ...(sessionExists ? {} : { WT_EXEC: omo.map(quote).join(" ") }),
          },
        })
      } catch (e) {
        const err = e as { stdout?: string; stderr?: string; message: string }
        failure = (err.stderr || err.stdout || err.message).trim()
      }
      ctx.ui.setStatus("wt", undefined)
      // Gate on .git, not wt's status: wt ends on tmux calls that can fail
      // with the worktree fine, the way wtoc found out.
      if (!existsSync(join(wtPath, ".git"))) {
        if (moved) spawnSync("sh", ["-c", `rm -f ${quote(moved)}; rmdir ${quote(moved.replace(/\.jsonl$/, "-artifacts"))}`])
        return ctx.ui.notify(`wt failed: ${failure || `see ${dir}/.${name}.log`}`, "error")
      }

      if (sessionExists) {
        const win = tmux("new-window", "-t", `=${session}:`, "-c", wtPath, ...omo)
        if (win.status !== 0) return ctx.ui.notify(`wt: tmux new-window failed: ${win.stderr}`, "error")
      }
      tmux("switch-client", "-t", `=${session}`)

      // Server-side, because killing the window kills this process. Waits for
      // omo to actually exit before deleting its file (and its sidecars). The
      // -artifacts dir goes only when empty: forkFrom doesn't copy it, and the
      // transcript refers to spilled tool output there by absolute path.
      const cleanup = [
        `tmux kill-window -t ${quote(oldWindow)}`,
        original && moved
          ? `i=0; while kill -0 ${process.pid} 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; ` +
            `kill -0 ${process.pid} 2>/dev/null || { rm -f ${quote(original)} ${quote(original)}.*; ` +
            `rmdir ${quote(original.replace(/\.jsonl$/, "-artifacts"))}; }`
          : "",
      ]
        .filter(Boolean)
        .join("; ")
      tmux("run-shell", "-b", `{ ${cleanup}; } >/dev/null 2>&1 || true`)
    },
  })
}
