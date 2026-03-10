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

-- Hyper + Space → Toggle between Ghostty and Cursor; default to Ghostty
local spaceCode = hs.keycodes.map["space"]
if spaceCode then
  hyperActionsByKeyCode[spaceCode] = function()
    local front = hs.application.frontmostApplication()
    local name = front and front:name() or ""
    if name == "Ghostty" then
      local cursor = hs.application.get("Cursor")
      if cursor then
        cursor:activate()
      else
        hs.execute("open -na Cursor", true)
      end
    else
      local ghostty = hs.application.get("Ghostty")
      if ghostty then
        ghostty:activate()
      else
        hs.execute("open -na Ghostty", true)
      end
    end
  end
end

-- Hyper + N → Focus Ghostty and jump to last tmux notification (prefix + N)
local nCode = hs.keycodes.map["n"]
if nCode then
  hyperActionsByKeyCode[nCode] = function()
    local app = hs.application.get("Ghostty")
    if app then
      app:activate()
      hs.timer.doAfter(0.05, function()
        hs.eventtap.keyStroke({ "ctrl" }, "space", 0)
        hs.timer.doAfter(0.05, function()
          hs.eventtap.keyStroke({ "shift" }, "n", 0)
        end)
      end)
    else
      hs.execute("open -na Ghostty", true)
    end
  end
end

local f18Watcher = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
  function(event)
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
      -- Return events from the callback: uses CGEventTapPostEvent (no
      -- reentrancy, no 1ms usleep per :post() call).
      return true, {
        newKeyEvent(binding[1], binding[2], true),
        newKeyEvent(binding[1], binding[2], false),
      }
    end

    -- Check action bindings.
    local action = hyperActionsByKeyCode[keyCode]
    if action then
      hyperUsedAsModifier = true
      action()
      return true
    end

    return false
  end
)

f18Watcher:start()

-- Monitor eventtap health: macOS can silently disable eventtaps that take too
-- long to return. If our watcher gets disabled, restart it.
local healthCheck = hs.timer.new(5, function()
  if not f18Watcher:isEnabled() then
    f18Watcher:start()
  end
end)
healthCheck:start()

-- Reset hyper state on system wake (sleep/wake often drops key events).
local caffeinate = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then
    resetHyper()
    if not f18Watcher:isEnabled() then
      f18Watcher:start()
    end
  end
end)
caffeinate:start()
