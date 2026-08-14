// Captures @explore / @librarian / @oracle subagent findings so future sessions
// can read prior research before re-doing it.  Solves cross-time work
// duplication without adding A2A tools to agent context.  All operations are
// wrapped in try/catch — this plugin must NEVER break the host opencode session.
//
// Storage layout — the git *common* dir, so every linked worktree of a repo
// shares one set of findings.  Findings describe the codebase, not the branch,
// and a fresh `git worktree add` is exactly when prior research is most useful.
// Living inside `.git` means nothing here is trackable, so no .gitignore is
// needed, and bare-repo layouts work unchanged:
//   $(git rev-parse --git-common-dir)/opencode-cache/
//     └── <slug>-<id>.md    Finding: frontmatter + title + sections TOC + body.
//
// The index is built in memory at injection time from the directory contents,
// so deletions/edits self-heal with no separate index file to keep in sync.
//
// Eviction is LRU with mtime as the clock: set on write, refreshed whenever an
// agent reads the finding.  Anything untouched for PRUNE_MS is deleted during
// the next index build.  The filesystem already tracks last-use, so there is no
// access log, no counter, and no separate state to keep in sync.

import type { Plugin } from "@opencode-ai/plugin";
import {
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  unlinkSync,
  utimesSync,
  writeFileSync,
} from "fs";
import { join } from "path";
import { spawnSync } from "child_process";

const CACHE_DIR_NAME = "opencode-cache";
const SUBAGENT_PATTERN = /\(@(explore|librarian|oracle)\s+subagent\)\s*$/i;
const MIN_BODY_LEN = 32;
const PRUNE_MS = 14 * 24 * 60 * 60 * 1000;

const contextPreamble = (dir: string) =>
  `
## Cached Research

Prior findings from @explore / @librarian / @oracle subagents in this repo. One
cache is shared by every worktree, so a finding may have been written from a
different branch than the one checked out here.

**These are leads, not facts.** Each was true when written and decays from that
moment. Measured against this cache: ~40% of file references are already dead or
moved, and line numbers rot first — treat any \`file:line\` here as stale.

Use them to see what was already investigated and where to look. Before acting on
a claim, confirm it in the repo: re-locate code by symbol name, never by the line
number quoted. Where a finding and the working tree disagree, the working tree
wins.

Frontmatter \`commit:\` is the sha the finding was written against. To see exactly
what has moved under it:
\`git diff --stat <commit>..HEAD -- <paths it cites>\`

Read the full body via \`${dir}/<filename>\`. Each starts with a
\`Sections:\` line for skimming; frontmatter \`created:\` tells you how much decay
to expect.

Delete on sight if wrong or superseded: \`rm ${dir}/<filename>\`.
`.trim();

type AgentType = "explore" | "librarian" | "oracle";

type MessagePart = { type?: string; text?: string };
type MessageInfo = { id?: string; role?: string; time?: { created?: number } };
type MessageEntry = { info?: MessageInfo; parts?: MessagePart[] };

type SessionData = {
  title?: string;
  parentID?: string | null;
  time?: { created?: number; updated?: number };
};

type Client = {
  session: {
    get: (args: { path: { id: string } }) => Promise<{ data?: SessionData }>;
    messages?: (args: {
      path: { id: string };
    }) => Promise<{ data?: MessageEntry[] }>;
  };
};

type EventInput = {
  event: { type: string; properties: Record<string, any> };
};

function gitOut(dir: string, args: string[]): string | null {
  try {
    const res = spawnSync("git", args, {
      cwd: dir,
      encoding: "utf8",
      timeout: 1000,
    });
    if (res.status !== 0) return null;
    const out = res.stdout.trim();
    return out.length > 0 ? out : null;
  } catch {
    return null;
  }
}

function resolveCacheDir(dir: string): string | null {
  const common = gitOut(dir, [
    "rev-parse",
    "--path-format=absolute",
    "--git-common-dir",
  ]);
  return common ? join(common, CACHE_DIR_NAME) : null;
}

function resolveHead(dir: string): string | null {
  return gitOut(dir, ["rev-parse", "--short", "HEAD"]);
}

function detectAgentType(title: string): AgentType | null {
  const m = title.match(SUBAGENT_PATTERN);
  return m ? (m[1].toLowerCase() as AgentType) : null;
}

function slugify(s: string): string {
  return (
    s
      .replace(SUBAGENT_PATTERN, "")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60) || "untitled"
  );
}

function shortId(sessionID: string): string {
  return sessionID.replace(/^ses_/, "").slice(-8);
}

function isoFromMs(ms?: number): string {
  if (!ms || !Number.isFinite(ms)) return "";
  return new Date(ms).toISOString();
}

function lastAssistantText(messages: MessageEntry[]): string {
  let latest: MessageEntry | null = null;
  let latestT = Number.NEGATIVE_INFINITY;
  for (const m of messages) {
    if (m?.info?.role !== "assistant") continue;
    const t = m.info?.time?.created ?? Number.NEGATIVE_INFINITY;
    if (t > latestT) {
      latestT = t;
      latest = m;
    }
  }
  if (!latest || !Array.isArray(latest.parts)) return "";
  return latest.parts
    .filter((p) => p?.type === "text" && typeof p.text === "string")
    .map((p) => (p.text as string).trim())
    .filter((t) => t.length > 0)
    .join("\n\n");
}

function extractHeadings(body: string): string[] {
  const headings: string[] = [];
  for (const line of body.split("\n")) {
    const m = line.match(/^(#{2,3})\s+(.+?)\s*$/);
    if (m) headings.push(m[2].trim());
  }
  return headings;
}

function escapeFmValue(s: string): string {
  if (/[:"\n#]/.test(s)) return JSON.stringify(s);
  return s;
}

function parseFrontMatter(content: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (!content.startsWith("---\n")) return out;
  const end = content.indexOf("\n---\n", 4);
  if (end === -1) return out;
  const block = content.slice(4, end);
  for (const line of block.split("\n")) {
    const i = line.indexOf(":");
    if (i === -1) continue;
    const k = line.slice(0, i).trim();
    let v = line.slice(i + 1).trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      try {
        v = JSON.parse(v);
      } catch {}
    }
    if (k.length > 0) out[k] = v;
  }
  return out;
}

function buildFinding(opts: {
  title: string;
  topic: string;
  agent: AgentType;
  session: string;
  parent: string | null;
  commit: string | null;
  createdISO: string;
  updatedISO: string;
  body: string;
}): string {
  const fm: string[] = ["---"];
  fm.push(`topic: ${escapeFmValue(opts.topic)}`);
  fm.push(`agent: ${opts.agent}`);
  fm.push(`session: ${opts.session}`);
  if (opts.parent) fm.push(`parent: ${opts.parent}`);
  if (opts.commit) fm.push(`commit: ${opts.commit}`);
  fm.push(`created: ${opts.createdISO}`);
  fm.push(`updated: ${opts.updatedISO}`);
  fm.push("---");

  const headings = extractHeadings(opts.body);
  const parts: string[] = [fm.join("\n"), "", `# ${opts.title}`];
  if (headings.length > 0) {
    parts.push("", `**Sections:** ${headings.join(" · ")}`);
  }
  parts.push("", opts.body.trim(), "");
  return parts.join("\n");
}

function buildIndex(cacheDir: string): string {
  type Entry = { file: string; topic: string; agent: string; created: string };
  const entries: Entry[] = [];

  let names: string[] = [];
  try {
    names = readdirSync(cacheDir);
  } catch {
    return "";
  }

  for (const f of names) {
    if (!f.endsWith(".md") || f === "_index.md") continue;
    const path = join(cacheDir, f);
    try {
      if (Date.now() - statSync(path).mtimeMs > PRUNE_MS) {
        unlinkSync(path);
        continue;
      }
      const content = readFileSync(path, "utf8");
      const fm = parseFrontMatter(content);
      entries.push({
        file: f,
        topic: fm.topic ?? f,
        agent: fm.agent ?? "?",
        created: fm.created ?? "",
      });
    } catch {}
  }

  if (entries.length === 0) return "";

  entries.sort((a, b) =>
    a.created < b.created ? 1 : a.created > b.created ? -1 : 0,
  );

  return entries
    .map((e) => `- \`${e.file}\` (@${e.agent}) — ${e.topic}`)
    .join("\n");
}

export const FindingsCachePlugin: Plugin = async ({ client, directory }) => {
  // `directory` is the session's project root, but git-worktree setups can
  // disagree with opencode's view, and sessions launched from a subdir need
  // the worktree root resolved.  Fall through git for both.
  const cwdHint = directory ?? process.cwd();

  async function captureFinding(sessionID: string): Promise<void> {
    if (!sessionID) return;

    let title = "";
    let parentID: string | null = null;
    let createdMs = 0;
    let updatedMs = 0;
    try {
      const { data } = await client.session.get({ path: { id: sessionID } });
      title = (data?.title ?? "").trim();
      parentID = data?.parentID ?? null;
      createdMs = data?.time?.created ?? 0;
      updatedMs = data?.time?.updated ?? 0;
    } catch {
      return;
    }

    if (!parentID) return; // root session, not a subagent we care about
    if (!title || title.startsWith("<") || title.startsWith("{")) return; // title model hasn't run yet
    const agent = detectAgentType(title);
    if (!agent) return;

    const cacheDir = resolveCacheDir(cwdHint);
    if (!cacheDir) return;

    if (typeof client.session.messages !== "function") return;
    let body = "";
    try {
      const { data } = await client.session.messages({
        path: { id: sessionID },
      });
      if (Array.isArray(data)) body = lastAssistantText(data);
    } catch {
      return;
    }
    if (body.length < MIN_BODY_LEN) return;

    try {
      mkdirSync(cacheDir, { recursive: true });
      const topic = title.replace(SUBAGENT_PATTERN, "").trim();
      const filename = `${slugify(title)}-${shortId(sessionID)}.md`;
      const filepath = join(cacheDir, filename);
      const md = buildFinding({
        title,
        topic,
        agent,
        session: sessionID,
        parent: parentID,
        commit: resolveHead(cwdHint),
        createdISO: isoFromMs(createdMs) || new Date().toISOString(),
        updatedISO: isoFromMs(updatedMs) || new Date().toISOString(),
        body,
      });
      writeFileSync(filepath, md);
    } catch {}
  }

  return {
    event: async ({ event }: EventInput) => {
      if (event.type !== "session.idle") return;
      const props = event.properties ?? {};
      const sessionID: string | null =
        typeof props.sessionID === "string" && props.sessionID.length > 0
          ? props.sessionID
          : typeof props.info?.id === "string"
            ? props.info.id
            : null;
      if (!sessionID) return;
      await captureFinding(sessionID);
    },

    "tool.execute.after": async (input: { tool?: string; args?: unknown }) => {
      if (String(input?.tool ?? "").toLowerCase() !== "read") return;
      const path = (input?.args as Record<string, unknown> | undefined)?.path;
      if (
        typeof path !== "string" ||
        !path.includes(`/${CACHE_DIR_NAME}/`) ||
        !path.endsWith(".md")
      )
        return;
      try {
        const now = new Date();
        utimesSync(path, now, now);
      } catch {}
    },

    "experimental.chat.system.transform": async (_input, output) => {
      const cacheDir = resolveCacheDir(cwdHint);
      if (!cacheDir) return;
      const index = buildIndex(cacheDir);
      if (!index) return;
      output.system.push(`${contextPreamble(cacheDir)}\n\n${index}`);
    },
  };
};

export default FindingsCachePlugin;
