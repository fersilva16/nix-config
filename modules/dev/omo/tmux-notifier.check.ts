// Run: bun run modules/dev/omo/tmux-notifier.check.ts
//
// Covers @oc-status and the completion notification: the pane must stay busy
// -- and silent -- while a background task launched by the session has not
// woken it yet, then go idle and notify once the wake has landed.
import assert from "assert"
import { spawnSync } from "child_process"
import { appendFileSync, chmodSync, mkdtempSync, readFileSync, writeFileSync } from "fs"
import { tmpdir } from "os"
import { join } from "path"
import type { Ctx, Pi, RunMessage } from "./tmux-notifier"

// Fake `tmux` and `tmux-opencode-manager` on PATH; Bun resolves child binaries
// against the PATH it started with, hence the re-exec.
if (!process.env.OMO_CHECK_DIR) {
  const dir = mkdtempSync(join(tmpdir(), "omo-tmux-notifier-check-"))
  for (const [bin, log] of [
    ["tmux", "tmux.log"],
    ["tmux-opencode-manager", "notify.log"],
  ]) {
    const path = join(dir, bin)
    writeFileSync(path, `#!/bin/sh\nprintf '%s\\n' "$*" >> ${join(dir, log)}\nexit 0\n`)
    chmodSync(path, 0o755)
  }
  const { status } = spawnSync(process.execPath, [import.meta.path], {
    stdio: "inherit",
    env: {
      ...process.env,
      OMO_CHECK_DIR: dir,
      PATH: `${dir}:${process.env.PATH ?? ""}`,
      TMUX_PANE: "%1",
      OPENCODE_TMUX_NOTIFIER_SOUND: "0",
      OPENCODE_TMUX_NOTIFIER_DESKTOP: "0",
      OPENCODE_TMUX_NOTIFIER_IDLE_DELAY_MS: "0",
    },
  })
  process.exit(status ?? 1)
}

const dir = process.env.OMO_CHECK_DIR
const tmuxLog = join(dir, "tmux.log")
const notifyLog = join(dir, "notify.log")
const transcript = join(dir, "session.jsonl")
writeFileSync(tmuxLog, "")
writeFileSync(notifyLog, "")
writeFileSync(transcript, "")

const { default: extension, pendingBackgroundTasks } = await import("./tmux-notifier.ts")

const launch = (id: string) =>
  JSON.stringify({
    type: "message",
    message: { role: "toolResult", toolName: "task", content: [{ type: "text", text: `Started task x (${id}, running).` }] },
  })
const wake = (id: string) =>
  JSON.stringify({ type: "custom_message", customType: "omo-senpi:wake", content: `task completion name:${id} id:${id} status:completed` })

assert.deepStrictEqual([...pendingBackgroundTasks([launch("st_a"), launch("st_b"), wake("st_a")].join("\n"))], ["st_b"])

// One event shape wide enough for every handler the extension registers.
type AnyEvent = { messages?: RunMessage[]; name?: string }
const handlers = new Map<string, (event: AnyEvent, ctx: Ctx) => void>()
const pi: Pi = {
  cwd: "/tmp/check",
  sessionKind: "interactive",
  on: (name: string, fn: (event: AnyEvent, ctx: Ctx) => void) => {
    handlers.set(name, fn)
  },
  events: { on: () => {} },
}
extension(pi)
const ctx: Ctx = {
  cwd: "/tmp/check",
  isIdle: () => true,
  sessionManager: { getSessionId: () => "sid-1", getSessionFile: () => transcript },
}
const emit = (name: string, event: AnyEvent = {}) => handlers.get(name)?.(event, ctx)
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

function paneStatus(): string {
  const last = readFileSync(tmuxLog, "utf8")
    .split("\n")
    .filter((l) => l.includes("@oc-status"))
    .pop()
  return last?.split(/\s+/).pop() ?? ""
}

// One agent run that ends the way a real one does: settle, then the debounce.
async function run(): Promise<boolean> {
  writeFileSync(notifyLog, "")
  emit("agent_start")
  assert.strictEqual(paneStatus(), "busy", "busy while running")
  emit("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] })
  emit("agent_settled")
  await sleep(400)
  return readFileSync(notifyLog, "utf8").includes("--event complete")
}

emit("session_start")
assert.ok(readFileSync(tmuxLog, "utf8").includes("@oc-sid sid-1"), "claims the pane")
assert.strictEqual(paneStatus(), "idle")

appendFileSync(transcript, launch("st_bg") + "\n")
assert.ok(!(await run()), "silent while a background task is still running")
assert.strictEqual(paneStatus(), "busy", "busy until the task wakes the session")

appendFileSync(transcript, wake("st_bg") + "\n")
assert.ok(await run(), "notifies once the task has woken the session")
assert.strictEqual(paneStatus(), "idle")

console.log("omo tmux-notifier check: ok")
process.exit(0)
