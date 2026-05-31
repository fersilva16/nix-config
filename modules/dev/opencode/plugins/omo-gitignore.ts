// Auto-bootstraps a `.gitignore` containing `*` inside agent-managed scratch
// folders (e.g. `.omo/`, created by oh-my-openagent for plans/state) so their
// contents are never accidentally committed.
//
// The `.omo` folder is created by the oh-my-openagent plugin, which we don't
// control, so we bootstrap the ignore file reactively: whenever a tool runs or
// any session event fires, we cheaply check whether a managed folder exists at
// the worktree root and, if so, drop a `*` .gitignore once.
//
// Mirrors the lazy-bootstrap approach used by findings-cache.ts. All operations
// are wrapped in try/catch — this plugin must NEVER break the host session.
//
//   .omo/
//     └── .gitignore   `*`  — ignores everything in this folder, including
//                       itself. Written once; never tracked by git.

import type { Plugin } from "@opencode-ai/plugin";
import { existsSync, statSync, writeFileSync } from "fs";
import { join } from "path";
import { spawnSync } from "child_process";

// Folders that should always carry a `*` .gitignore once they appear.
const MANAGED_DIRS = [".omo"];

function resolveWorktreeRoot(dir: string): string | null {
  try {
    const res = spawnSync("git", ["rev-parse", "--show-toplevel"], {
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

function ensureGitignore(root: string, dirName: string): boolean {
  // Returns true once the managed dir is fully handled (gitignore present or
  // dir confirmed absent of need), so callers can stop re-checking it.
  try {
    const dir = join(root, dirName);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) return false;
    const gi = join(dir, ".gitignore");
    // `*` ignores everything in this folder, including the .gitignore itself.
    if (!existsSync(gi)) writeFileSync(gi, "*\n");
    return true;
  } catch {
    return false;
  }
}

export const OmoGitignorePlugin: Plugin = async ({ directory }) => {
  const cwdHint = directory ?? process.cwd();

  // Resolve the worktree root once (spawning git is comparatively expensive).
  let cachedRoot: string | null | undefined;
  function getRoot(): string | null {
    if (cachedRoot === undefined) {
      cachedRoot = resolveWorktreeRoot(cwdHint) ?? cwdHint;
    }
    return cachedRoot;
  }

  // Track which managed dirs are done so repeated events short-circuit.
  const handled = new Set<string>();

  function sweep(): void {
    try {
      if (handled.size >= MANAGED_DIRS.length) return;
      const root = getRoot();
      if (!root) return;
      for (const dirName of MANAGED_DIRS) {
        if (handled.has(dirName)) continue;
        if (ensureGitignore(root, dirName)) handled.add(dirName);
      }
    } catch {}
  }

  return {
    // Most timely trigger: fires right after the write/bash tool that creates
    // the managed folder.
    "tool.execute.after": async () => {
      sweep();
    },
    // Backstop in case the folder is created outside a tracked tool call.
    event: async () => {
      sweep();
    },
  };
};

export default OmoGitignorePlugin;
