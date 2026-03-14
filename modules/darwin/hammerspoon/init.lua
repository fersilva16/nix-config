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

if not hs.accessibilityState() then
  hs.alert.show("Hammerspoon needs Accessibility access!", 5)
end

local hyperDown = false
local hyperUsedAsModifier = false

local function resetHyper()
  hyperDown = false
end

-- Pre-build keyCode→{mods, key} binding table at init time.
-- This merges the keycodes.map lookup and the "is this key bound?" check
-- into a single integer-keyed table hit in the hot path.
local newKeyEvent = hs.eventtap.event.newKeyEvent

local hyperBindingsByKeyCode = {}
local hyperActionsByKeyCode = {}

local bindingDefs = {
  h = { {},        "left" },
  j = { {},        "down" },
  k = { {},        "up" },
  l = { {},        "right" },
  [";"] = { { "cmd" }, "right" },
}

for char, binding in pairs(bindingDefs) do
  local code = hs.keycodes.map[char]
  if code then
    -- Pre-create the event constructor args: store mods and target key
    hyperBindingsByKeyCode[code] = binding
  end
end

-- Hyper + T → Open a new Ghostty window
local tCode = hs.keycodes.map["t"]
if tCode then
  hyperActionsByKeyCode[tCode] = function()
    hs.execute("open -na Ghostty", true)
  end
end

-- Hyper + C → Open Cursor at the git root of the current tmux pane directory
local cCode = hs.keycodes.map["c"]
if cCode then
  hyperActionsByKeyCode[cCode] = function()
    local dir = hs.execute("tmux display-message -p '#{pane_current_path}' 2>/dev/null", true)
    dir = dir and dir:gsub("%s+$", "") or ""
    if dir ~= "" then
      local gitRoot = hs.execute(string.format("git -C '%s' rev-parse --show-toplevel 2>/dev/null", dir), true)
      gitRoot = gitRoot and gitRoot:gsub("%s+$", "") or ""
      local target = gitRoot ~= "" and gitRoot or dir
      hs.execute(string.format("open -a Cursor '%s'", target), true)
    else
      hs.execute("open -a Cursor", true)
    end
  end
end

-- Hyper + Space → Toggle between Ghostty and Cursor; default to Ghostty
local spaceCode = hs.keycodes.map["space"]
if spaceCode then
  hyperActionsByKeyCode[spaceCode] = function()
    local front = hs.application.frontmostApplication()
    local bid = front and front:bundleID() or ""
    if bid == "com.mitchellh.ghostty" then
      hs.application.open("Cursor")
    else
      hs.application.open("Ghostty")
    end
  end
end

-- Hyper + N → Focus Ghostty and jump to last tmux notification (prefix + N)
local nCode = hs.keycodes.map["n"]
if nCode then
  hyperActionsByKeyCode[nCode] = function()
    local wasRunning = hs.application.get("com.mitchellh.ghostty") ~= nil
    hs.application.open("Ghostty")
    if wasRunning then
      hs.timer.doAfter(0.1, function()
        hs.eventtap.keyStroke({ "ctrl" }, "space", 0)
        hs.timer.doAfter(0.05, function()
          hs.eventtap.keyStroke({ "shift" }, "n", 0)
        end)
      end)
    end
  end
end

-- Eventtap callback, extracted so we can recreate the tap without duplication.
local function f18Callback(event)
  local keyCode = event:getKeyCode()

  -- F18 = keyCode 79
  if keyCode == 79 then
    local eventType = event:getType()
    if eventType == hs.eventtap.event.types.keyDown then
      if not hyperDown then
        hyperDown = true
        hyperUsedAsModifier = false
      end
      return true
    elseif eventType == hs.eventtap.event.types.keyUp then
      local wasTap = not hyperUsedAsModifier
      resetHyper()
      if wasTap then
        hs.hid.capslock.toggle()
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
    return true, {
      newKeyEvent(mods, binding[2], true),
      newKeyEvent(mods, binding[2], false),
    }
  end

  -- Check action bindings.
  -- Actions are deferred to the next run-loop iteration so the eventtap
  -- callback returns immediately. macOS silently disables CGEventTaps
  -- whose callbacks exceed ~300ms; hs.execute() can easily hit that.
  local action = hyperActionsByKeyCode[keyCode]
  if action then
    hyperUsedAsModifier = true
    hs.timer.doAfter(0, function()
      local ok, err = pcall(action)
      if not ok then
        hs.alert.show("Hyper action error: " .. tostring(err), 3)
      end
    end)
    return true
  end

  return false
end

local f18Watcher = nil
local tapEventTypes = { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }

-- Destroy the current tap and create a fresh one. macOS can permanently
-- invalidate a CGEventTap handle; re-enabling it via :start() does nothing
-- in that case. Recreating from scratch gets a new Mach port.
local function recreateWatcher()
  if f18Watcher then
    f18Watcher:stop()
    f18Watcher = nil
  end
  f18Watcher = hs.eventtap.new(tapEventTypes, f18Callback)
  f18Watcher:start()
  resetHyper()
end

recreateWatcher()

-- Monitor eventtap health every 2 seconds. If the tap has been silently
-- disabled by macOS, destroy it and create a brand new one.
local healthCheck = hs.timer.new(2, function()
  if not f18Watcher or not f18Watcher:isEnabled() then
    hs.alert.show("⌨️ Hyper key recovered", 1.5)
    recreateWatcher()
  end
end)
healthCheck:start()

-- Full reload on system wake. Sleep can permanently invalidate eventtap
-- Mach ports, freeze timers, and leave watchers unresponsive. A clean
-- reload is the only reliable recovery.
local caffeinate = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake or
    event == hs.caffeinate.watcher.screensDidWake then
    hs.timer.doAfter(2, function()
      hs.reload()
    end)
  end
end)
caffeinate:start()

-- Auto-reload config on changes with debounce. The config is a nix store
-- symlink, so darwin-rebuild changes the symlink target which can fire
-- multiple events in quick succession. A 2-second debounce collapses them
-- into a single reload.
local reloadTimer = nil
local configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function()
  if reloadTimer then
    reloadTimer:stop()
  end
  reloadTimer = hs.timer.doAfter(2, function()
    hs.reload()
  end)
end)
configWatcher:start()
