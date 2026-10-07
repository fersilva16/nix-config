// Subscription rate limits for every account in omo's credential store: both
// Claude logins and the ChatGPT one. The sidebar's Limits block renders them.
//
// Tokens come from ~/.omo/agent/auth.json and are only ever read. omo owns
// their lifecycle and refreshes them while it is in use, which is exactly when
// this is on screen; refreshing here would rotate the refresh token out from
// under omo.
//
// Every open omo polls, so results are shared through a cache file in TMPDIR:
// each one re-reads it every READ_MS, and whichever finds it older than TTL_MS
// and wins the lock file fetches while the rest just read.
//
// TTL_MS is antiburn's cadence, and a failed fetch waits it out too, as in
// antiburn: Anthropic's usage endpoint answers a one-minute poll with 429 and
// `retry-after: 0`, which gives nothing better to wait for.
import { readFileSync, renameSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"
import { requestRender } from "./host.ts"
import { lock, unlock } from "./lock.ts"

// `seconds` is the window's full length, which pace needs to know how much of
// it has elapsed.
export type Window = { label: string; percent: number; resetsAt: number | undefined; seconds?: number }
// `provider` groups accounts in the sidebar; `name` is omo's account name.
export type Account = { provider: string; name: string; windows: Window[]; error?: string }

type Auth = {
  "anthropic-subscription"?: { accounts?: { name: string; access: string }[] }
  "chatgpt-subscription"?: { access?: string; accountId?: string }
}
type Cache = { at: number; accounts: Account[] }

const AUTH = join(homedir(), ".omo/agent/auth.json")
const CACHE = join(tmpdir(), "omo-limits.json")
const LOCK = `${CACHE}.lock`
const TTL_MS = 5 * 60_000
const READ_MS = 30_000
const TIMEOUT_MS = 8_000
// /reload imports a fresh copy of this module; the timer lives on globalThis
// so the new copy replaces the old poller instead of running beside it.
const TIMER = Symbol.for("omo-ui.limits.timer")

export const limits = { accounts: [] as Account[] }

async function getJson(url: string, headers: Record<string, string>): Promise<any> {
  const res = await fetch(url, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

async function claude(token: string): Promise<Window[]> {
  const usage = await getJson("https://api.anthropic.com/api/oauth/usage", {
    Authorization: `Bearer ${token}`,
    "anthropic-beta": "oauth-2025-04-20",
  })
  return (
    [
      ["five_hour", "5h", 5 * 3_600],
      ["seven_day", "7d", 7 * 86_400],
    ] as const
  ).flatMap(([key, label, seconds]) => {
    const w = usage[key]
    return w ? [{ label, percent: w.utilization, resetsAt: w.resets_at ? Date.parse(w.resets_at) : undefined, seconds }] : []
  })
}

async function codex(token: string, accountId: string): Promise<Window[]> {
  const usage = await getJson("https://chatgpt.com/backend-api/wham/usage", {
    Authorization: `Bearer ${token}`,
    "chatgpt-account-id": accountId,
    "User-Agent": "codex_cli_rs",
  })
  const span = (s: number) => (s >= 86_400 ? `${Math.round(s / 86_400)}d` : `${Math.round(s / 3_600)}h`)
  const rl = usage.rate_limit ?? {}
  return [rl.primary_window, rl.secondary_window]
    .filter(Boolean)
    .map((w) => ({
      label: span(w.limit_window_seconds),
      percent: w.used_percent,
      resetsAt: w.reset_at * 1000,
      seconds: w.limit_window_seconds,
    }))
}

function readCache(): Cache | undefined {
  try {
    return JSON.parse(readFileSync(CACHE, "utf8"))
  } catch {
    return undefined
  }
}

async function poll(): Promise<void> {
  const cached = readCache()
  if (cached) {
    limits.accounts = cached.accounts
    requestRender()
  }
  if (cached && Date.now() - cached.at < TTL_MS) return
  if (!lock(LOCK)) return
  try {
    // Another omo may have finished a fetch between the read above and
    // taking the lock.
    const latest = readCache()
    if (latest && Date.now() - latest.at < TTL_MS) {
      limits.accounts = latest.accounts
      requestRender()
      return
    }
    let auth: Auth
    try {
      auth = JSON.parse(readFileSync(AUTH, "utf8"))
    } catch {
      // No omo login at all: nothing to meter, so the block stays hidden.
      return
    }
    const jobs: [provider: string, name: string, run: () => Promise<Window[]>][] = (
      auth["anthropic-subscription"]?.accounts ?? []
    ).map((a) => ["claude", a.name, () => claude(a.access)])
    const chatgpt = auth["chatgpt-subscription"]
    if (chatgpt?.access && chatgpt.accountId) jobs.push(["codex", "codex", () => codex(chatgpt.access!, chatgpt.accountId!)])

    // A failed fetch keeps that account's last numbers, flagged with the
    // error: a blank row would read as "plenty left". The sidebar drops any
    // window past its reset, so carried numbers expire on their own.
    const previous = new Map(limits.accounts.map((a) => [`${a.provider}/${a.name}`, a.windows]))
    limits.accounts = await Promise.all(
      jobs.map(([provider, name, run]) =>
        run().then(
          (windows): Account => ({ provider, name, windows }),
          (e: unknown): Account => ({
            provider,
            name,
            windows: previous.get(`${provider}/${name}`) ?? [],
            error: e instanceof Error ? e.message : String(e),
          }),
        ),
      ),
    )
    writeCache(limits.accounts)
    requestRender()
  } finally {
    unlock(LOCK)
  }
}

function writeCache(accounts: Account[]): void {
  const tmp = `${CACHE}.${process.pid}`
  writeFileSync(tmp, JSON.stringify({ at: Date.now(), accounts } satisfies Cache))
  renameSync(tmp, CACHE)
}

export function startLimits(): void {
  const slots = globalThis as Record<symbol, ReturnType<typeof setInterval> | undefined>
  clearInterval(slots[TIMER])
  const timer = setInterval(() => void poll(), READ_MS)
  // Never the reason omo's process stays alive on exit.
  ;(timer as { unref?(): void }).unref?.()
  slots[TIMER] = timer
  void poll()
}
