// Run: bun run modules/dev/opencode-manager/plugins/tmux-notifier.check.ts
//
// Covers only @oc-status: the pane must read busy while a subagent works,
// even though the parent session itself went idle to wait for it.
import assert from "assert";
import { spawnSync } from "child_process";
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

// The plugin shells out to `tmux`, so the check runs against a fake one on
// PATH. Bun resolves a child binary against the PATH it was started with, not
// process.env, hence the re-exec instead of an in-process mutation.
if (!process.env.OC_CHECK_DIR) {
  const dir = mkdtempSync(join(tmpdir(), "tmux-notifier-check-"));
  const fakeTmux = join(dir, "tmux");
  writeFileSync(fakeTmux, `#!/bin/sh\nprintf '%s\\n' "$*" >> ${join(dir, "tmux.log")}\nexit 0\n`);
  chmodSync(fakeTmux, 0o755);
  const { status } = spawnSync(process.execPath, [import.meta.path], {
    stdio: "inherit",
    env: {
      ...process.env,
      OC_CHECK_DIR: dir,
      PATH: `${dir}:${process.env.PATH ?? ""}`,
      TMUX_PANE: "%1",
      TMUX_NOTIFY_FILE: join(dir, "notifications.json"),
      OPENCODE_TMUX_NOTIFIER_SOUND: "0",
      OPENCODE_TMUX_NOTIFIER_DESKTOP: "0",
      OPENCODE_TMUX_NOTIFIER_IDLE_DELAY_MS: "0",
    },
  });
  process.exit(status ?? 1);
}

const log = join(process.env.OC_CHECK_DIR, "tmux.log");
writeFileSync(log, "");

const { default: TmuxNotifierPlugin } = await import("./tmux-notifier.ts");

const client = {
  session: {
    get: async () => ({ data: { title: "check", parentID: null } }),
    messages: async () => ({ data: [] }),
  },
};

const hooks = await TmuxNotifierPlugin({ client, directory: "/tmp/check" });
const emit = (type: string, properties: Record<string, any>) => hooks.event?.({ event: { type, properties } });

function paneStatus(): string {
  const last = readFileSync(log, "utf8")
    .split("\n")
    .filter((l) => l.includes("@oc-status"))
    .pop();
  return last?.split(/\s+/).pop() ?? "";
}

await emit("session.created", { info: { id: "parent" } });
await emit("session.status", { sessionID: "parent", status: { type: "busy" } });
assert.strictEqual(paneStatus(), "busy", "own session busy");

await emit("session.created", { info: { id: "child", parentID: "parent" } });
await emit("session.status", { sessionID: "child", status: { type: "busy" } });
await emit("session.idle", { sessionID: "parent" });
assert.strictEqual(paneStatus(), "busy", "parent idle but child still working");

await emit("session.idle", { sessionID: "child" });
assert.strictEqual(paneStatus(), "idle", "child settled");

await emit("session.created", { info: { id: "child2", parentID: "parent" } });
await emit("session.status", { sessionID: "child2", status: { type: "busy" } });
assert.strictEqual(paneStatus(), "busy", "second child busy");
await emit("session.error", { sessionID: "child2", error: { name: "MessageAbortedError" } });
assert.strictEqual(paneStatus(), "idle", "cancelled child releases the pane");

console.log("tmux-notifier check: ok");
process.exit(0);
