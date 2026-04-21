-- Hyper key implementation using F18 (mapped from Caps Lock via hidutil)
--
-- hidutil remaps Caps Lock → F18 at the kernel level (zero latency).
-- This script turns F18 into a "Hyper" modifier when held with other keys,
-- and toggles Caps Lock when tapped alone.
--
-- Performance design:
--   - Single eventtap, no hs.hotkey.modal (avoids hotkey register/unregister
--     overhead on every caps press/release).
--   - Hyper bindings return events from the callback via the table return
--     pattern (uses CGEventTapPostEvent instead of CGEventPost, avoiding the
--     1ms usleep per event in :post(), and preventing reentrancy — synthetic
--     events skip our tap entirely).
--   - Pre-built keyCode→binding lookup table (one integer-keyed table hit
--     instead of hs.keycodes.map + string lookup per event).
--   - Fast path: non-F18 events when hyper is not held are rejected with a
--     single boolean check + integer comparison, no function calls.
--
-- Diagnostics:
--   Logs to ~/.hammerspoon/hyper.log (auto-rotates at 256 KB).
--   Tail live:  tail -f ~/.hammerspoon/hyper.log
--   Last 50:    tail -50 ~/.hammerspoon/hyper.log

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
local LOG_PATH = os.getenv("HOME") .. "/.hammerspoon/hyper.log"
local LOG_MAX_BYTES = 256 * 1024

-- Rotate: if current log exceeds limit, move to .old and start fresh.
local function rotateLog()
  local f = io.open(LOG_PATH, "r")
  if not f then return end
  local size = f:seek("end")
  f:close()
  if size and size > LOG_MAX_BYTES then
    os.remove(LOG_PATH .. ".old")
    os.rename(LOG_PATH, LOG_PATH .. ".old")
  end
end

local function log(category, msg)
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  local now = hs.timer.secondsSinceEpoch()
  local ms = math.floor((now % 1) * 1000)
  f:write(string.format("[%s.%03d] %-8s | %s\n", os.date("%Y-%m-%dT%H:%M:%S"), ms, category, msg))
  f:close()
end

rotateLog()
log("INIT", "======== Hammerspoon hyper key loading ========")

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
hs.allowAppleScript(true)

if not hs.accessibilityState() then
  hs.alert.show("Hammerspoon needs Accessibility access!", 5)
  log("ERROR", "Missing Accessibility access")
end

-- ---------------------------------------------------------------------------
-- ⚠️  CRITICAL: GARBAGE COLLECTION RETENTION ⚠️
-- ---------------------------------------------------------------------------
-- READ THIS BEFORE MODIFYING ANY hs.timer / hs.caffeinate.watcher /
-- hs.pathwatcher / hs.eventtap CODE IN THIS FILE.
--
-- Hammerspoon objects (timers, watchers, taps) have __gc finalizers that
-- STOP the underlying OS object (NSTimer, NSWorkspace observer, FSEvents
-- stream, CGEventTap) when the Lua userdata is garbage-collected.
-- Hammerspoon does NOT retain these objects internally — it relies entirely
-- on the user to keep a Lua-side reference alive.
--
-- This means: if you write `local myTimer = hs.timer.new(...)` at chunk
-- scope, the `myTimer` local goes out of scope the moment init.lua finishes
-- executing. Lua's GC eventually (typically ~10-15 minutes in) collects the
-- userdata. The __gc finalizer invalidates the NSTimer. The timer SILENTLY
-- STOPS FIRING. No error, no log, no indication of failure.
--
-- We learned this the hard way. Diagnostic instrumentation caught the
-- signature: hs.timer.new(2, ...) fired perfectly (drift=0.00s) for
-- 12.5 minutes and then stopped cold. hs.caffeinate.watcher never fired
-- a single event despite 58 sleep/wake cycles.
--
-- THE FIX: All long-lived observer objects MUST be retained via the global
-- retention table `_G.__hsHyperRetain` declared below. Anything created
-- with hs.timer.new, hs.caffeinate.watcher.new, hs.pathwatcher.new,
-- or hs.eventtap.new that needs to outlive the init.lua chunk execution
-- MUST be assigned to this table.
--
-- Exceptions: objects reassigned from inside a function that's itself
-- retained (e.g., f18Watcher is mutated inside recreateWatcher, which is
-- an upvalue of healthCheck's callback — so f18Watcher stays reachable
-- through the healthCheck→recreateWatcher chain).
--
-- References:
--   https://github.com/asmagill/hammerspoon/wiki/Variable-Scope-and-Garbage-Collection
--   https://github.com/Hammerspoon/hammerspoon/issues/1713
--   https://github.com/Hammerspoon/hammerspoon/issues/2202
--   https://github.com/Hammerspoon/hammerspoon/issues/2416
--   https://github.com/Hammerspoon/hammerspoon/issues/3001
--   https://github.com/Hammerspoon/hammerspoon/issues/3102
--   https://github.com/Hammerspoon/hammerspoon/issues/3300
--   https://github.com/Hammerspoon/hammerspoon/issues/3557
--
-- Source code proof (Hammerspoon extensions/timer/libtimer.m timer_gc):
--   [timer stop];  // ← invalidates NSTimer on GC
--   timer.fnRef = [skin luaUnref:refTable ref:timer.fnRef];
--
-- hs.reload() creates a fresh Lua state, so resetting the table on each
-- init is safe: old state is cleaned up via __gc, new table is empty.
_G.__hsHyperRetain = {}
local retain = _G.__hsHyperRetain

local hyperDown = false
local hyperUsedAsModifier = false
local hyperDownSince = nil   -- epoch timestamp when hyperDown was set
local lastEventTime = nil    -- epoch timestamp of last event through the tap
local tapEventCount = 0      -- events processed since last tap creation

-- Diagnostic counters (NEVER reset across recreates) for forensic analysis
-- of the "timer dies but eventtap keeps running" failure mode. Compare these
-- against HEALTH ticks to see which subsystem stopped first.
local totalTapEvents = 0     -- events ever processed by f18 tap, for lifetime
local TAP_HEARTBEAT_EVERY = 100  -- emit TAP marker every N events

local function resetHyper()
  hyperDown = false
  hyperDownSince = nil
end

-- Pre-build keyCode→{mods, key} binding table at init time.
-- This merges the keycodes.map lookup and the "is this key bound?" check
-- into a single integer-keyed table hit in the hot path.
local newKeyEvent = hs.eventtap.event.newKeyEvent

local hyperBindingsByKeyCode = {}
local hyperActionsByKeyCode = {}

local bindingDefs = {
  h = { {}, "left" },
  j = { {}, "down" },
  k = { {}, "up" },
  l = { {}, "right" },
  [";"] = { { "cmd" }, "right" },
}

for char, binding in pairs(bindingDefs) do
  local code = hs.keycodes.map[char]
  if code then
    hyperBindingsByKeyCode[code] = binding
  end
end

-- Reverse lookup for logging: keyCode → readable name
local keyCodeNames = {}
for char, _ in pairs(bindingDefs) do
  local code = hs.keycodes.map[char]
  if code then keyCodeNames[code] = char end
end

-- Hyper + T → Open a new Ghostty window
-- Uses hs.task (async) to avoid blocking the main thread.
local tCode = hs.keycodes.map["t"]
if tCode then
  keyCodeNames[tCode] = "t"
  hyperActionsByKeyCode[tCode] = function()
    hs.task.new("/usr/bin/open", nil, { "-na", "Ghostty" }):start()
  end
end

-- Hyper + C → Open Cursor at the git root of the current tmux pane directory.
-- Uses hs.task (async) instead of hs.execute to avoid blocking the main
-- thread — a hung tmux/git would otherwise cause macOS to disable the tap.
--
-- Resolving "the current tmux session" from outside tmux:
--   `tmux display-message -p '#{pane_current_path}'` without a target is
--   ambiguous when multiple sessions exist — tmux falls back to an internal
--   default (often the first/oldest session) rather than the one the user
--   is actually attached to. We fix this by picking the most recently
--   active *client* (sorted by client_activity), then resolving that
--   client's session's active pane path. If no client is attached, the
--   command produces empty output and the existing fallback opens Cursor
--   without a path.
local cCode = hs.keycodes.map["c"]
if cCode then
  keyCodeNames[cCode] = "c"
  hyperActionsByKeyCode[cCode] = function()
    hs.task.new("/bin/sh", function(_code, stdout)
      local dir = stdout and stdout:gsub("%s+$", "") or ""
      if dir == "" then
        hs.task.new("/usr/bin/open", nil, { "-a", "Cursor" }):start()
        return
      end
      hs.task.new("/bin/sh", function(_code2, stdout2)
        local gitRoot = stdout2 and stdout2:gsub("%s+$", "") or ""
        local target = gitRoot ~= "" and gitRoot or dir
        hs.task.new("/usr/bin/open", nil, { "-a", "Cursor", target }):start()
      end, { "-l", "-c", string.format("git -C '%s' rev-parse --show-toplevel 2>/dev/null", dir) }):start()
    end, { "-l", "-c", "S=$(tmux list-clients -F '#{client_activity}|#{client_session}' 2>/dev/null | sort -rn | head -1 | cut -d'|' -f2); [ -n \"$S\" ] && tmux display-message -p -t \"$S\" '#{pane_current_path}' 2>/dev/null" }):start()
  end
end

-- Hyper + Space → Toggle between Ghostty and Cursor; default to Ghostty.
-- Uses hs.task (async) — hs.application.open() blocks the main thread and
-- freezes all timers when an app is slow to respond to Launch Services.
local spaceCode = hs.keycodes.map["space"]
if spaceCode then
  keyCodeNames[spaceCode] = "space"
  hyperActionsByKeyCode[spaceCode] = function()
    local front = hs.application.frontmostApplication()
    local bid = front and front:bundleID() or ""
    if bid == "com.mitchellh.ghostty" then
      hs.task.new("/usr/bin/open", nil, { "-a", "Cursor" }):start()
    else
      hs.task.new("/usr/bin/open", nil, { "-a", "Ghostty" }):start()
    end
  end
end

-- Hyper + N → Focus Ghostty and jump to last tmux notification (prefix + N)
-- Keys are posted directly to Ghostty via :post(app) (CGEventPostToPSN) so
-- they bypass our eventtap — otherwise Ctrl+Space triggers hyper+space.
local nCode = hs.keycodes.map["n"]
if nCode then
  keyCodeNames[nCode] = "n"
  hyperActionsByKeyCode[nCode] = function()
    local ghostty = hs.application.get("com.mitchellh.ghostty")
    if not ghostty then
      hs.task.new("/usr/bin/open", nil, { "-a", "Ghostty" }):start()
      return
    end
    ghostty:activate()
    hs.timer.doAfter(0.1, function()
      local g = hs.application.get("com.mitchellh.ghostty")
      if g then
        newKeyEvent({ "ctrl" }, "space", true):post(g)
        newKeyEvent({ "ctrl" }, "space", false):post(g)
        hs.timer.doAfter(0.05, function()
          local g2 = hs.application.get("com.mitchellh.ghostty")
          if g2 then
            newKeyEvent({ "shift" }, "n", true):post(g2)
            newKeyEvent({ "shift" }, "n", false):post(g2)
          end
        end)
      end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Eventtap callback
-- ---------------------------------------------------------------------------
local function f18Callback(event)
  local keyCode = event:getKeyCode()
  lastEventTime = hs.timer.secondsSinceEpoch()
  tapEventCount = tapEventCount + 1
  totalTapEvents = totalTapEvents + 1
  if totalTapEvents % TAP_HEARTBEAT_EVERY == 0 then
    log("TAP", string.format("alive total=%d", totalTapEvents))
  end

  -- F18 = keyCode 79
  if keyCode == 79 then
    local eventType = event:getType()
    if eventType == hs.eventtap.event.types.keyDown then
      if not hyperDown then
        hyperDown = true
        hyperUsedAsModifier = false
        hyperDownSince = lastEventTime
        log("HYPER", "DOWN")
      end
      return true
    elseif eventType == hs.eventtap.event.types.keyUp then
      local wasTap = not hyperUsedAsModifier
      local heldFor = hyperDownSince and (lastEventTime - hyperDownSince) or 0
      resetHyper()
      if wasTap then
        hs.hid.capslock.toggle()
        log("HYPER", string.format("UP tap (caps toggled) held=%.2fs", heldFor))
      else
        log("HYPER", string.format("UP modifier held=%.2fs", heldFor))
      end
      return true
    end
  end

  -- Fast path: if hyper is not held, bail immediately (one boolean check).
  if not hyperDown then
    return false
  end

  -- Hyper is held — only care about keyDown events for bindings.
  if event:getType() ~= hs.eventtap.event.types.keyDown then
    return false
  end

  -- Check arrow/key remappings (integer-keyed table lookup, no string ops).
  local binding = hyperBindingsByKeyCode[keyCode]
  if binding then
    hyperUsedAsModifier = true
    -- Pass through modifier flags (shift, option, cmd) so that e.g.
    -- Hyper+Shift+h → Shift+Left (select), Hyper+Option+h → Option+Left
    -- (word jump), Hyper+Cmd+h → Cmd+Left (line start), and any
    -- combination thereof.
    local flags = event:getFlags()
    local mods = {}
    for _, m in ipairs(binding[1]) do
      mods[#mods + 1] = m
    end
    if flags.shift then mods[#mods + 1] = "shift" end
    if flags.alt then mods[#mods + 1] = "alt" end
    if flags.cmd then mods[#mods + 1] = "cmd" end
    local name = keyCodeNames[keyCode] or tostring(keyCode)
    log("BIND", string.format("%s → %s (mods: %s)", name, binding[2], table.concat(mods, "+") or "none"))
    return true, {
      newKeyEvent(mods, binding[2], true),
      newKeyEvent(mods, binding[2], false),
    }
  end

  -- Check action bindings.
  -- Actions are one-shot; ignore key repeats (bindings above allow repeats
  -- intentionally — e.g. holding Hyper+H sends repeated Left arrows).
  -- Actions are deferred to the next run-loop iteration so the eventtap
  -- callback returns immediately. macOS silently disables CGEventTaps
  -- whose callbacks exceed ~300ms; hs.execute() can easily hit that.
  local action = hyperActionsByKeyCode[keyCode]
  if action then
    hyperUsedAsModifier = true
    if event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0 then
      return true
    end
    local name = keyCodeNames[keyCode] or tostring(keyCode)
    log("ACTION", name)
    hs.timer.doAfter(0, function()
      local ok, err = pcall(action)
      if not ok then
        log("ERROR", "action " .. name .. ": " .. tostring(err))
        hs.alert.show("Hyper action error: " .. tostring(err), 3)
      end
    end)
    return true
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Arrow key blocker
-- ---------------------------------------------------------------------------
-- Force hjkl usage by blocking the physical arrow keys. The hyper+hjkl
-- remapping still works: the f18 tap's CGEventTapPostEvent posts synthetic
-- arrow events, and while those events do flow through this tap, they only
-- occur while F18 (hyper) is held — so a single `hyperDown` check is enough
-- to distinguish "user pressed hjkl with hyper" from "user pressed a real
-- arrow key". Real arrow presses always happen with hyperDown == false.
--
-- Arrow key codes: left=123, right=124, down=125, up=126
local arrowKeyCodes = {
  [123] = "left",
  [124] = "right",
  [125] = "down",
  [126] = "up",
}

-- Retained via _G.__hsHyperRetain — see GC warning at top of file.
retain.arrowBlocker = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
  function(event)
    if hyperDown then return false end
    local name = arrowKeyCodes[event:getKeyCode()]
    if name then
      if event:getType() == hs.eventtap.event.types.keyDown
          and event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then
        log("BLOCK", "arrow " .. name)
      end
      return true
    end
    return false
  end
)
retain.arrowBlocker:start()

-- ---------------------------------------------------------------------------
-- Tap lifecycle
-- ---------------------------------------------------------------------------
local f18Watcher = nil
local tapEventTypes = { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }

-- Check if the hidutil Caps Lock → F18 mapping is still active.
-- Returns true if the mapping is present, false otherwise.
local function checkHidutilMapping()
  local raw = hs.execute("/usr/bin/hidutil property --get UserKeyMapping 2>/dev/null", false)
  if not raw then return false end
  -- Look for our specific mapping: Caps Lock (0x700000039) → F18 (0x70000006D)
  return raw:find("30064771129") ~= nil and raw:find("30064771181") ~= nil
end

-- Destroy the current tap and create a fresh one. macOS can permanently
-- invalidate a CGEventTap handle; re-enabling it via :start() does nothing
-- in that case. Recreating from scratch gets a new Mach port.
local function recreateWatcher(reason)
  reason = reason or "unknown"
  local prevCount = tapEventCount
  if f18Watcher then
    f18Watcher:stop()
    f18Watcher = nil
  end
  f18Watcher = hs.eventtap.new(tapEventTypes, f18Callback)
  f18Watcher:start()
  resetHyper()
  tapEventCount = 0

  local hidutilOk = checkHidutilMapping()
  log("RECREATE", string.format(
    "reason=%s prev_events=%d hidutil_mapping=%s",
    reason, prevCount, hidutilOk and "ok" or "MISSING"))

  if not hidutilOk then
    log("ERROR", "hidutil Caps Lock → F18 mapping is MISSING — hyper key will not work")
    hs.alert.show("⚠️ Caps Lock → F18 mapping lost!\nRun: sudo darwin-rebuild switch --flake .#m1", 8)
  end
end

recreateWatcher("init")

-- ---------------------------------------------------------------------------
-- Health monitoring
-- ---------------------------------------------------------------------------

-- Secure Input monitoring state. When an app enables Secure Input (password
-- fields, 1Password, etc.), ALL CGEventTaps are blocked — events stop flowing
-- even though isEnabled() still returns true. Track consecutive ticks to
-- distinguish brief password dialogs from stuck Secure Input.
local secureInputTicks = 0
local SECURE_INPUT_ALERT_TICKS = 5   -- first alert after 10s (5 × 2s)
local SECURE_INPUT_REMIND_TICKS = 15 -- re-alert every 30s while stuck

-- Proactive tap recreation. macOS can silently invalidate a CGEventTap's
-- Mach port in ways that isEnabled() doesn't detect. Periodically destroying
-- and recreating the tap gets a fresh Mach port as prevention.
local lastRecreate = hs.timer.secondsSinceEpoch()
local RECREATE_INTERVAL = 30 -- 30 seconds (was 300; kept short to cap outage window)

-- Stuck-hyper threshold. If hyperDown has been true for longer than this,
-- it's almost certainly stuck (missed F18 keyUp). Force-reset it.
local STUCK_HYPER_THRESHOLD = 5 -- seconds

-- Timer-liveness diagnostics. macOS can throttle NSTimer-backed callbacks
-- during display-idle periods even with NSAppSleepDisabled set (see
-- Hammerspoon issue #1942 for the related sleep case). Tracking tick count
-- and inter-tick gap lets us forensically distinguish three failure modes:
--   1. Timer dies clean: ticks stop entirely (totalHealthTicks frozen)
--   2. Timer drifts:     gaps balloon to seconds/minutes between ticks
--   3. Timer is fine:    gaps stay near 2s, ticks keep incrementing
local totalHealthTicks = 0
local lastHealthTickTime = nil
local HEALTH_HEARTBEAT_EVERY = 15  -- log a TICK marker every 30s (15 × 2s)
local HEALTH_DRIFT_THRESHOLD = 1.0 -- log immediately if a tick is >1s late

-- Monitor eventtap health every 2 seconds with four layers of protection:
-- 1. Reactive:    detect tap disabled by macOS and recreate.
-- 2. Proactive:   recreate every 30s to get a fresh Mach port.
-- 3. Stuck hyper: detect hyperDown stuck for >5s and force-reset.
-- 4. Secure Input: detect when events are blocked despite a "healthy" tap.
-- The entire callback is pcall-wrapped so the recovery mechanism itself
-- cannot die from an unexpected error.
-- Retained via _G.__hsHyperRetain — see GC warning at top of file.
retain.healthCheck = hs.timer.new(2, function()
  local ok, err = pcall(function()
    local now = hs.timer.secondsSinceEpoch()
    local lastEvtAgo = lastEventTime and (now - lastEventTime) or -1

    totalHealthTicks = totalHealthTicks + 1
    local sinceLastTick = lastHealthTickTime and (now - lastHealthTickTime) or 0
    lastHealthTickTime = now
    local drift = sinceLastTick - 2
    if totalHealthTicks % HEALTH_HEARTBEAT_EVERY == 0 or drift > HEALTH_DRIFT_THRESHOLD then
      log("TICK", string.format(
        "n=%d gap=%.2fs drift=%+.2fs tap_total=%d",
        totalHealthTicks, sinceLastTick, drift, totalTapEvents))
    end

    -- 1. Reactive: tap explicitly disabled by macOS
    if not f18Watcher or not f18Watcher:isEnabled() then
      log("HEALTH", string.format("REACTIVE: tap disabled — recreating (last_evt=%.1fs ago)", lastEvtAgo))
      hs.alert.show("⌨️ Hyper key recovered", 1.5)
      recreateWatcher("reactive:tap_disabled")
      lastRecreate = now
      secureInputTicks = 0
      return
    end

    -- 2. Proactive: recreate every RECREATE_INTERVAL seconds
    if now - lastRecreate >= RECREATE_INTERVAL then
      log("HEALTH", string.format(
        "PROACTIVE: %ds elapsed — recreating (last_evt=%.1fs ago, events=%d)",
        RECREATE_INTERVAL, lastEvtAgo, tapEventCount))
      recreateWatcher("proactive:" .. RECREATE_INTERVAL .. "s")
      lastRecreate = now
    end

    -- 3. Stuck hyper: hyperDown is true but no events flowing through the tap.
    --    Active use (holding hyper + pressing hjkl) keeps lastEventTime fresh,
    --    so this only fires when the tap died mid-hold and stopped receiving
    --    events entirely.
    if hyperDown and hyperDownSince then
      local lastActivity = lastEventTime or hyperDownSince
      local silentFor = now - lastActivity
      if silentFor > STUCK_HYPER_THRESHOLD then
        log("HEALTH", string.format(
          "STUCK: hyperDown with no events for %.1fs (held for %.1fs) — force resetting",
          silentFor, now - hyperDownSince))
        hs.alert.show("⌨️ Hyper key unstuck", 1.5)
        resetHyper()
      end
    end

    -- 4. Secure Input: alert user with culprit process name.
    --    isEnabled() returns true under Secure Input, so this is the only
    --    way to detect this failure mode.
    if hs.eventtap.isSecureInputEnabled() then
      secureInputTicks = secureInputTicks + 1
      local shouldAlert = secureInputTicks == SECURE_INPUT_ALERT_TICKS
          or (secureInputTicks > SECURE_INPUT_ALERT_TICKS
              and (secureInputTicks - SECURE_INPUT_ALERT_TICKS) % SECURE_INPUT_REMIND_TICKS == 0)
      if shouldAlert then
        local culprit = "unknown"
        local raw = hs.execute(
            "/usr/bin/ioreg -l -w 0 | /usr/bin/grep kCGSSessionSecureInputPID | /usr/bin/head -1", false)
        if raw then
          local pid = raw:match("= (%d+)")
          if pid and pid ~= "0" then
            local name = hs.execute("/bin/ps -p " .. pid .. " -o comm= 2>/dev/null", false)
            if name and name:gsub("%s+$", "") ~= "" then
              culprit = name:gsub("%s+$", ""):match("[^/]+$") or ("PID " .. pid)
            else
              culprit = "PID " .. pid
            end
          end
        end
        log("SECURE", string.format("Secure Input ON for %ds — culprit: %s", secureInputTicks * 2, culprit))
        hs.alert.show("⚠️ Secure Input ON — hyper key blocked\nCulprit: " .. culprit, 6)
      end
    else
      if secureInputTicks > 0 then
        log("SECURE", string.format("Secure Input OFF after %ds", secureInputTicks * 2))
      end
      secureInputTicks = 0
    end
  end)
  if not ok then
    log("ERROR", "health check: " .. tostring(err))
    hs.alert.show("⌨️ Health check error: " .. tostring(err), 3)
  end
end)
retain.healthCheck:start()

-- ---------------------------------------------------------------------------
-- Power / session event handler
-- ---------------------------------------------------------------------------

-- macOS can freeze Hammerspoon's run loop and invalidate eventtap Mach ports
-- across a variety of power/session transitions. The built-in health checks
-- can't catch all of these because the run loop itself may be paused during
-- the transition, so we react directly to the transition events.
--
-- Upstream issue describing the underlying NSTimer-pauses-during-sleep bug:
--   https://github.com/Hammerspoon/hammerspoon/issues/1942
--
-- Severity ladder:
--   HEAVY (full hs.reload): system/screen sleep → wake. These can pause timers
--     for arbitrary durations and permanently invalidate Mach ports. Only a
--     full reload is guaranteed to recover.
--   LIGHT (recreate tap only): screen unlock, screensaver stop, session
--     reactivation. Usually the Lua state is fine; the tap just needs a
--     fresh Mach port and hyper state needs resetting in case a keyUp was
--     missed while the screen was locked.
--   PASSIVE (log only): going-inactive events (lock, sleep, resign). Nothing
--     to recover yet — just annotate the log so post-mortem analysis can
--     correlate outages with the transition that preceded them.

local caffeinateWatcher = hs.caffeinate.watcher

local heavyReloadEvents = {
  [caffeinateWatcher.systemDidWake] = "systemDidWake",
  [caffeinateWatcher.screensDidWake] = "screensDidWake",
}

local lightRecoveryEvents = {
  [caffeinateWatcher.screensDidUnlock] = "screensDidUnlock",
  [caffeinateWatcher.screensaverDidStop] = "screensaverDidStop",
  [caffeinateWatcher.sessionDidBecomeActive] = "sessionDidBecomeActive",
}

local passiveLogEvents = {
  [caffeinateWatcher.systemWillSleep] = "systemWillSleep",
  [caffeinateWatcher.screensDidSleep] = "screensDidSleep",
  [caffeinateWatcher.screensDidLock] = "screensDidLock",
  [caffeinateWatcher.screensaverDidStart] = "screensaverDidStart",
  [caffeinateWatcher.sessionDidResignActive] = "sessionDidResignActive",
  [caffeinateWatcher.systemWillPowerOff] = "systemWillPowerOff",
}

-- Retained via _G.__hsHyperRetain — see GC warning at top of file.
retain.caffeinate = caffeinateWatcher.new(function(event)
  local ok, err = pcall(function()
    -- Always log the event first, before any branching. This is the
    -- diagnostic baseline: if we ever see "broken" with no POWER entries,
    -- we know macOS isn't delivering caffeinate notifications at all.
    local eventName = heavyReloadEvents[event]
        or lightRecoveryEvents[event]
        or passiveLogEvents[event]
        or ("unknown:" .. tostring(event))
    log("POWER", "received " .. eventName)

    if heavyReloadEvents[event] then
      log("POWER", "scheduling full reload in 2s (" .. eventName .. ")")
      hs.timer.doAfter(2, function()
        log("POWER", "Reloading now (" .. eventName .. ")")
        hs.reload()
      end)
    elseif lightRecoveryEvents[event] then
      log("POWER", "light recovery in 0.5s (" .. eventName .. ")")
      -- Small delay so macOS has fully finished the transition before we
      -- ask for a new Mach port. Observed on Sonoma: recreating a tap in
      -- the same tick as screensDidUnlock can produce a tap that starts
      -- disabled.
      hs.timer.doAfter(0.5, function()
        recreateWatcher("power:" .. eventName)
        lastRecreate = hs.timer.secondsSinceEpoch()
        secureInputTicks = 0
      end)
    end
  end)
  if not ok then
    log("ERROR", "power handler: " .. tostring(err))
    hs.alert.show("⌨️ Power handler error: " .. tostring(err), 3)
  end
end)
retain.caffeinate:start()

-- ---------------------------------------------------------------------------
-- Config watcher
-- ---------------------------------------------------------------------------

-- Auto-reload config on changes with debounce. The config is a nix store
-- symlink, so darwin-rebuild changes the symlink target which can fire
-- multiple events in quick succession. A 2-second debounce collapses them
-- into a single reload.
local reloadTimer = nil
-- Retained via _G.__hsHyperRetain — see GC warning at top of file.
retain.configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(changedPaths)
  local ok, err = pcall(function()
    if changedPaths then
      local configChanged = false
      for _, p in ipairs(changedPaths) do
        if not p:match("%.log") then
          configChanged = true
          break
        end
      end
      if not configChanged then return end
    end
    log("RELOAD", "Config change detected — debouncing 2s")
    if reloadTimer then
      reloadTimer:stop()
    end
    reloadTimer = hs.timer.doAfter(2, function()
      log("RELOAD", "Reloading now")
      hs.reload()
    end)
  end)
  if not ok then
    log("ERROR", "config watcher: " .. tostring(err))
    hs.alert.show("⌨️ Config watcher error: " .. tostring(err), 3)
  end
end)
retain.configWatcher:start()

log("INIT", "======== Hyper key ready ========")
