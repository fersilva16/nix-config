// Run: bun run modules/dev/omo/notifier/tmux-notifier.check.ts
//
// Covers the pane options: the pane must stay busy -- and silent -- while
// something will wake the session, then go idle and flag @agent-attn once
// nothing will; a new run clears the flag and a clean exit clears everything.
import assert from "assert"
import { spawnSync } from "child_process"
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "fs"
import { tmpdir } from "os"
import { join } from "path"
import type { Ctx, Pi, RunMessage } from "./tmux-notifier"

// Fake `tmux` and `afplay` on PATH, both logging to one file; Bun resolves
// child binaries against the PATH it started with, hence the re-exec.
const FAKES = ["tmux", "afplay"]
if (!process.env.OMO_CHECK_DIR) {
  const dir = mkdtempSync(join(tmpdir(), "omo-tmux-notifier-check-"))
  for (const bin of FAKES) {
    const path = join(dir, bin)
    writeFileSync(path, `#!/bin/sh\nprintf '%s %s\\n' ${bin} "$*" >> ${join(dir, "calls.log")}\nexit 0\n`)
    chmodSync(path, 0o755)
  }
  const { status } = spawnSync(process.execPath, [import.meta.path], {
    stdio: "inherit",
    env: { ...process.env, OMO_CHECK_DIR: dir, PATH: `${dir}:${process.env.PATH ?? ""}`, TMUX_PANE: "%1" },
  })
  process.exit(status ?? 1)
}

const log = join(process.env.OMO_CHECK_DIR, "calls.log")
// First exec of a freshly written script pays macOS's scan, which can exceed
// the extension's 300ms tmux timeout; pay it here, not in the first assertion.
for (const bin of FAKES) spawnSync(bin, [])
writeFileSync(log, "")

const { default: extension } = await import("./tmux-notifier.ts")

// Replays the logged tmux calls into the pane's option table.
function options(): Map<string, string> {
  const opts = new Map<string, string>()
  for (const line of readFileSync(log, "utf8").split("\n")) {
    if (!line.startsWith("tmux ")) continue
    for (const cmd of line.slice(5).split(" ; ")) {
      const [name, flags, , , opt, value] = cmd.split(" ")
      if (name !== "set-option") continue
      if (flags === "-pu") opts.delete(opt)
      else opts.set(opt, value)
    }
  }
  return opts
}
const status = () => options().get("@agent-status")
const attn = () => options().get("@agent-attn")

type AnyEvent = { messages?: RunMessage[]; name?: string }
const handlers = new Map<string, (event: AnyEvent, ctx: Ctx) => void>()
type BusPayload = { source?: string; activeCount?: number; active?: boolean; label?: string }
const bus = new Map<string, (payload: BusPayload) => void>()
const pi: Pi = {
  sessionKind: "interactive",
  on: (name: string, fn: (event: AnyEvent, ctx: Ctx) => void) => {
    handlers.set(name, fn)
  },
  events: {
    on: (channel: string, fn: (payload: BusPayload) => void) => {
      bus.set(channel, fn)
    },
  },
}
extension(pi, 0)
const ctx: Ctx = { cwd: "/tmp/check", isIdle: () => true, sessionManager: { getSessionId: () => "sid-1" } }
const emit = (name: string, event: AnyEvent = {}) => handlers.get(name)?.(event, ctx)
const wakeSource = (source: string, activeCount: number) => bus.get("wake_source_state")?.({ source, activeCount })
// The debounce is a 0ms timer; a timer queued after it fires after it.
const debounce = () => new Promise((r) => setTimeout(r, 0))

async function run(stopReason = "stop") {
  emit("agent_start")
  assert.strictEqual(status(), "busy", "busy while running")
  assert.strictEqual(attn(), undefined, "a new run clears the attention flag")
  emit("agent_end", { messages: [{ role: "assistant", stopReason }] })
  emit("agent_settled")
  await debounce()
}

emit("session_start")
assert.strictEqual(options().get("@agent-sid"), "sid-1", "claims the pane")
assert.strictEqual(status(), "idle")

await run()
assert.strictEqual(attn(), "complete")
assert.strictEqual(status(), "idle")
assert.ok(options().get("@agent-attn-at"), "timestamps the flag")

// Background tasks, monitors, detached eval cells: omo's wake sources.
wakeSource("senpi-task", 1)
wakeSource("terminal-monitors", 1)
await run()
assert.strictEqual(attn(), undefined, "silent while a wake source is live")
assert.strictEqual(status(), "busy", "busy until the wake sources drain")
wakeSource("senpi-task", 0)
await debounce()
assert.strictEqual(attn(), undefined, "still silent with one source left")
wakeSource("terminal-monitors", 0)
await debounce()
assert.strictEqual(attn(), "complete", "flags once the last source drains")
assert.strictEqual(status(), "idle")

// A pending ask-user question is the user's move, not background work.
wakeSource("ask-user", 1)
await run()
assert.strictEqual(attn(), "complete", "an open question does not hold the completion")

await run("error")
assert.strictEqual(attn(), "error")

bus.get("herdr:blocked")?.({ active: true, label: "Q" })
assert.strictEqual(attn(), "question")

emit("session_shutdown")
assert.deepStrictEqual([...options().keys()], [], "a clean exit leaves no options behind")

console.log("omo tmux-notifier check: ok")
process.exit(0)
