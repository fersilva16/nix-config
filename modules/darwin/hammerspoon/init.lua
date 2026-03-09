-- Hyper key implementation using F18 (mapped from Caps Lock via hidutil)
--
-- hidutil remaps Caps Lock → F18 at the kernel level (zero latency).
-- This script turns F18 into a "Hyper" modifier (Ctrl+Opt+Shift+Cmd)
-- when held with other keys, and toggles Caps Lock when tapped alone.

local hyperMode = hs.hotkey.modal.new()

-- Track whether F18 was used as a modifier
local hyperUsedAsModifier = false

-- Track the F18 key down event for tap detection
local f18Down = false

-- Hyper + hjkl → Arrow keys
-- Hyper + ; → Cmd+Right (end of line)
local hyperBindings = {
	{ "h", {}, "left" },
	{ "j", {}, "down" },
	{ "k", {}, "up" },
	{ "l", {}, "right" },
	{ ";", { "cmd" }, "right" },
}

for _, binding in ipairs(hyperBindings) do
	local key, mods, arrow = binding[1], binding[2], binding[3]
	hyperMode:bind({}, key, function()
		hyperUsedAsModifier = true
		hs.eventtap.keyStroke(mods, arrow, 0)
	end, nil, function()
		hs.eventtap.keyStroke(mods, arrow, 0)
	end)
end

-- Watch for F18 key events
local f18Watcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, function(event)
	local keyCode = event:getKeyCode()

	-- F18 = keyCode 79
	if keyCode ~= 79 then
		return false
	end

	local eventType = event:getType()

	if eventType == hs.eventtap.event.types.keyDown then
		if not f18Down then
			f18Down = true
			hyperUsedAsModifier = false
			hyperMode:enter()
		end
		return true
	elseif eventType == hs.eventtap.event.types.keyUp then
		f18Down = false
		hyperMode:exit()

		-- If F18 was tapped alone, toggle Caps Lock
		if not hyperUsedAsModifier then
			hs.hid.capslock.toggle()
		end
		return true
	end

	return false
end)

f18Watcher:start()

-- Reload config on file changes
local configWatcher = hs.pathwatcher.new(hs.configdir, function(files)
	local doReload = false
	for _, file in pairs(files) do
		if file:sub(-4) == ".lua" then
			doReload = true
		end
	end
	if doReload then
		hs.reload()
	end
end)
configWatcher:start()
