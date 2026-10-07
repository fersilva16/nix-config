// Cross-process lock files for the caches every open omo shares in TMPDIR
// (core/limits.ts, core/git.ts): whichever omo takes the lock fetches while
// the rest just read the cache.
import { closeSync, openSync, statSync, unlinkSync } from "node:fs"

// Well past the longest a guarded fetch can run (each caller's timeouts stay
// under it), so a lock this old was left by an omo that died mid-fetch.
const STALE_MS = 30_000

// O_EXCL create is atomic across processes: exactly one omo gets the file.
// Any failure means "not ours this tick"; the next tick tries again.
export function lock(path: string): boolean {
  try {
    closeSync(openSync(path, "wx"))
    return true
  } catch {
    try {
      if (Date.now() - statSync(path).mtimeMs < STALE_MS) return false
      unlinkSync(path)
      closeSync(openSync(path, "wx"))
      return true
    } catch {
      return false
    }
  }
}

export function unlock(path: string): void {
  try {
    unlinkSync(path)
  } catch {
    // Already gone: another omo judged it stale and took it over.
  }
}
