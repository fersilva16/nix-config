// Run: bun run modules/dev/opencode/plugins/findings-cache.check.ts
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, unlinkSync, utimesSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { spawnSync } from "child_process";
import assert from "assert";

import FindingsCachePlugin from "./findings-cache.ts";

const DAY = 24 * 60 * 60 * 1000;

const root = mkdtempSync(join(tmpdir(), "fc-check-"));
const git = (...a: string[]) => spawnSync("git", a, { cwd: root, encoding: "utf8" });
git("init", "-q");
git("commit", "-q", "--allow-empty", "-m", "root", "--author=t <t@t>");
const cacheDir = join(root, ".opencode-cache");
mkdirSync(cacheDir);

function finding(name: string, topic: string, ageDays: number) {
  const p = join(cacheDir, name);
  writeFileSync(p, `---\ntopic: ${topic}\nagent: explore\ncreated: 2026-01-01T00:00:00.000Z\n---\n\n# ${topic}\n\nbody\n`);
  const t = new Date(Date.now() - ageDays * DAY);
  utimesSync(p, t, t);
  return p;
}

const fresh = finding("fresh-aaaaaaaa.md", "Fresh finding", 1);
const stale = finding("stale-bbbbbbbb.md", "Stale finding", 60);
const revived = finding("revived-cccccccc.md", "Old but recently read", 60);

const sessionID = "ses_deadbeefcafe01234567";
const client = {
  session: {
    get: async () => ({
      data: { title: "Check the write path (@explore subagent)", parentID: "ses_parent", time: { created: Date.now(), updated: Date.now() } },
    }),
    messages: async () => ({
      data: [{ info: { role: "assistant", time: { created: Date.now() } }, parts: [{ type: "text", text: "## Answer\n\nA body long enough to clear MIN_BODY_LEN." }] }],
    }),
  },
};

const plugin: any = await FindingsCachePlugin({ directory: root, client } as any);

await plugin.event({ event: { type: "session.idle", properties: { sessionID } } });
const written = join(cacheDir, "check-the-write-path-01234567.md");
assert(existsSync(written), "session.idle must capture a subagent finding");
const head = git("rev-parse", "--short", "HEAD").stdout.trim();
assert(readFileSync(written, "utf8").includes(`commit: ${head}`), "finding must record the sha it was written against");
unlinkSync(written);

// Reading an old-but-still-useful finding must refresh its LRU clock.
await plugin["tool.execute.after"]({ tool: "read", args: { path: revived } });
assert(Date.now() - statSync(revived).mtimeMs < DAY, "read must refresh mtime");

const out: { system: string[] } = { system: [] };
await plugin["experimental.chat.system.transform"]({}, out);

const survivors = readdirSync(cacheDir).filter((f) => f.endsWith(".md")).sort();
assert.deepStrictEqual(survivors, ["fresh-aaaaaaaa.md", "revived-cccccccc.md"], `stale entry must be evicted, got ${survivors}`);

const index = out.system.join("\n");
assert(index.includes("Fresh finding"), "index must list fresh entry");
assert(index.includes("Old but recently read"), "index must list revived entry");
assert(!index.includes("Stale finding"), "index must not list evicted entry");

// A read outside the cache dir must not be touched.
const other = join(root, "notes.md");
writeFileSync(other, "x");
const before = new Date(Date.now() - 60 * DAY);
utimesSync(other, before, before);
await plugin["tool.execute.after"]({ tool: "read", args: { path: other } });
assert(Date.now() - statSync(other).mtimeMs > 59 * DAY, "non-cache reads must be ignored");

console.log("PASS: captures with commit sha, evicts stale, keeps fresh, read revives LRU clock, ignores non-cache reads");