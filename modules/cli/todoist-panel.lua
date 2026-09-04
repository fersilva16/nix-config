-- Todoist ambient panel — the list itself, on screen all day, beside the work.
--
-- The tmux widget shows a COUNT, and only while a terminal is visible. This is
-- the other half: the actual rows, docked to one screen, above every window and
-- on every Space, so remembering is not a thing that has to be done on purpose.
--
-- Read-only, deliberately. Triage is hyper+T — the same picker as `t` in a pane
-- and prefix+t in tmux — and this surface is the reminder, not the tool. A panel
-- you can click is a panel you fiddle with instead of working, and the whole
-- point of an ambient surface is that it costs nothing to ignore.
--
-- Rows come from every *-panel-data on the profile, concatenated. That glob is
-- the whole plugin protocol: a module with something worth seeing all day
-- installs an executable with that suffix and prints state<TAB>text. Todoist
-- ships todoist-panel-data, linear ships linear-panel-data, and neither has to
-- know the other exists — except that todoist is not a guest here. This file
-- IS its panel, so its section always leads; everything else follows behind
-- it, separated by a blank line per section.
--
-- Each producer prints its OWN header as a head row, because each one owns the
-- definition its count is of — todoist-panel-data reads the SAME cache and the
-- same today/sort/priority definitions as the tmux widget. One definition, two
-- surfaces: a panel that disagreed with the count in the bar about what is due
-- today would make both of them untrustworthy, and a single total summed here
-- would start doing exactly that the moment a second producer appeared.
--
-- Loaded by init.lua's extras loader; see modules/cli/todoist.nix for the
-- home-manager drop and the _G.__todoistPanelCfg prelude it prepends.

-- ---------------------------------------------------------------------------
-- ⚠️  RETENTION — see the GC warning at the top of init.lua ⚠️
-- ---------------------------------------------------------------------------
-- hs.timer / hs.screen.watcher userdata have __gc finalizers that STOP the
-- underlying OS object. Nothing in Hammerspoon retains them for us, so a plain
-- `local t = hs.timer.new(...)` goes out of scope when this chunk finishes and
-- dies silently minutes later. Everything long-lived goes in this table.
_G.__todoistPanelRetain = {}
local retain = _G.__todoistPanelRetain

local cfg = _G.__todoistPanelCfg or {}
local WIDTH = cfg.width or 300
local SCREEN = cfg.screen
local EVERY = cfg.refresh or 60

-- Same reason init.lua spells out the path for tmux-todoist-pick: this file is
-- installed with `source =`, so nix cannot interpolate a store path into it.
--
-- /bin/sh because the glob IS the extension point for GUESTS: any other module
-- with something worth seeing all day drops its own *-panel-data on the
-- profile and shows up here without this file ever learning its name. Todoist
-- itself is not a guest — it owns this panel (installed by modules/cli/
-- todoist.nix) — so it runs first, named directly, and everyone else follows
-- in glob order.
--
-- The expansion lives inside the -c script rather than in this table because
-- hs.task hands arguments to the executable verbatim, never through a shell.
local DATA = "/bin/sh"
local DATA_ARGS = {
  "-c",
  [[
b="$HOME/.nix-profile/bin"
[ -x "$b/todoist-panel-data" ] && "$b/todoist-panel-data"
for f in "$b"/*-panel-data; do
  [ "$f" = "$b/todoist-panel-data" ] && continue
  [ -x "$f" ] && "$f"
done
]],
}

-- Flexoki Light — the palette the tmux widgets already use, and the theme
-- Ghostty is set to. The point is that this reads as one more pane of the
-- terminal rather than a widget parked beside it.
--
-- Fully opaque, because it owns its strip now (see the reservation below).
-- Translucency was for floating over windows; against a wallpaper it was most
-- of why the thing looked pasted on.
--
-- Written as rgb floats rather than {hex=...} so nothing here depends on which
-- colour-table spellings hs.drawing accepts. Hex kept alongside for grepping.
local COLORS = {
  bg = { red = 0.949, green = 0.941, blue = 0.898, alpha = 1.0 }, -- #F2F0E5 paper
  border = { red = 0.855, green = 0.847, blue = 0.808 }, -- #DAD8CE ui-2
  head = { red = 0.435, green = 0.431, blue = 0.412 }, -- #6F6E69 tx-2
  overdue = { red = 0.820, green = 0.302, blue = 0.255 }, -- #D14D41
  urgent = { red = 0.820, green = 0.302, blue = 0.255 }, -- #D14D41
  medium = { red = 0.816, green = 0.635, blue = 0.082 }, -- #D0A215
  normal = { red = 0.063, green = 0.059, blue = 0.059 }, -- #100F0F tx
}

-- Ghostty's exact font and size. The proportional font was the other half of
-- why this did not read as a terminal — nothing lined up down the left edge.
local FONT = { name = "CaskaydiaCove Nerd Font", size = 12 }

-- Tuned to the 12pt monospace above, so rows sit at terminal line spacing
-- rather than UI-list spacing.
local ROW_H = 17
local HEAD_H = 20
local PAD = 12

local panel = nil
-- The rows actually drawn, capped by rowBudget, plus the "+N more" line. The
-- producers' head rows are in here too and cost a slot each, because a section
-- heading occupies a line on screen like anything else.
local rows = {}

-- Both tables belong to init.lua, which resets them on every load; the fallback
-- is so this file still loads standalone (its own test does exactly that).
_G.__hsReserved = _G.__hsReserved or {}
_G.__hsHyperExtras = _G.__hsHyperExtras or {}

-- Persisted, not a plain local: init.lua does a full hs.reload() on every wake
-- and screen unlock, so an in-memory flag would put the panel back on screen
-- every time the lid opens — the one behaviour "collapsible" has to rule out.
local SETTING = "todoistPanelVisible"
local visible = hs.settings.get(SETTING)
if visible == nil then
  visible = true
end

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------

-- Falls back to primary whenever the configured screen is not attached, so
-- unplugging the external monitor moves the panel instead of losing it.
local function targetScreen()
  if SCREEN then
    local found = hs.screen.find(SCREEN)
    if found then
      return found
    end
  end
  return hs.screen.primaryScreen()
end

-- Claimed while the panel is toggled ON, regardless of how many rows are
-- showing. Tying the claim to the row count instead would resize every window
-- on the screen as tasks get completed through the day — a reserved edge is
-- only worth having if it stays put, so an empty list keeps the space and just
-- stops drawing in it.
local function reserve()
  local screen = visible and targetScreen() or nil
  _G.__hsReserved.todoistPanel = screen
      and { screen = screen:getUUID(), edge = "right", size = WIDTH }
    or nil
end

-- How many rows fit on the target screen — the ONLY bound. A row drawn past the
-- bottom edge is a row that is not there, so it has to be counted in "+N more"
-- rather than silently lost.
--
-- There used to be a maxTasks option capping this further, and it was the thing
-- collapsing rows into "+N more" on a screen with room for forty more. A second
-- smaller cap cannot make the list safer than the screen bound already does; it
-- can only hide work. An ambient panel earns its strip by showing everything
-- that fits, so the strip is the limit.
--
-- One rule instead of two. Clamping the panel HEIGHT to the screen was the
-- obvious alternative and is worse — it produces a box the right size with rows
-- painted outside it, so the list looks complete while hiding exactly the
-- overdue items the sort worked to float to the top.
--
-- The -1 reserves the "+N more" slot unconditionally. Reserving it only when
-- there is overflow costs a branch to save one row on a screen tall enough for
-- fifty, and this way the height is provably <= the screen by construction.
local function rowBudget()
  local screen = targetScreen()
  -- No display attached at all: render() draws nothing either way, so bound
  -- nothing rather than inventing a number and reporting rows as hidden. The
  -- next tick, with a screen, computes a real budget.
  if not screen then
    return math.huge
  end
  local fits = math.floor((screen:frame().h - (PAD * 2) - HEAD_H) / ROW_H) - 1
  if fits < 1 then
    fits = 1
  end
  return fits
end

-- :frame() rather than :fullFrame() — the usable area, so the panel starts
-- below the menu bar and stops above the Dock instead of sliding under either.
--
-- Full height, not the height of the content. It occupies a reserved strip, and
-- a strip that windows are kept out of has to look occupied for its whole
-- length: a short box floating in a tall empty column reads as a bug, not as a
-- short list. This also makes the height independent of the row count, so
-- nothing on screen moves as tasks are completed through the day.
local function place()
  if not panel then
    return
  end
  local screen = targetScreen()
  if not screen then
    return
  end
  local f = screen:frame()
  panel:frame({
    x = f.x + f.w - WIDTH,
    y = f.y,
    w = WIDTH,
    h = f.h,
  })
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function styled()
  -- No header of its own. Every line here came from a producer, including the
  -- head rows that name each section and carry its count.
  --
  -- The reward state still has to fill the pane. Silence was right when this
  -- was a floating box that could just vanish; now that it holds a reserved
  -- strip, drawing nothing would leave a tall empty column that looks broken.
  -- Reached only when NO producer said anything at all — a producer with an
  -- empty list still prints its own header, and todoist prints "nothing due"
  -- beneath it.
  if #rows == 0 then
    return hs.styledtext.new("nothing due", { font = FONT, color = COLORS.head })
  end

  local out
  for _, row in ipairs(rows) do
    local piece = hs.styledtext.new(row.text .. "\n", {
      font = FONT,
      color = COLORS[row.state] or COLORS.normal,
    })
    out = out and out .. piece or piece
  end
  return out
end

local function render()
  -- Collapsed is the only thing that hides it now. An empty list keeps the pane
  -- (see styled), because the strip stays reserved either way and an unoccupied
  -- reserved strip is just a hole in the desktop.
  if not visible then
    if panel then
      panel:hide()
    end
    return
  end

  if not panel then
    panel = hs.canvas.new({ x = 0, y = 0, w = WIDTH, h = 100 })
    -- floating = above ordinary windows, below system alerts.
    panel:level(hs.canvas.windowLevels.floating)
    -- canJoinAllSpaces so switching Spaces does not take the list away;
    -- stationary so Mission Control leaves it where it is.
    panel:behavior({ "canJoinAllSpaces", "stationary" })
    -- Swallow clicks. hs.canvas leaves ignoresMouseEvents on until a
    -- mouseCallback is registered, so without these two lines a click aimed at
    -- the panel lands on the Finder desktop behind it and sends every window
    -- away. Nothing is lost by absorbing it: the panel holds a RESERVED strip,
    -- so the desktop is the only thing back there.
    --
    -- The callback is deliberately empty. Read-only is the design (see the top
    -- of this file) — this stops the misfire, it does not add a surface to
    -- fiddle with. Making ROWS clickable is a different change: every row is
    -- one line inside a single text element, so each would have to become its
    -- own canvas element with its own frame before a click could name one.
    --
    -- clickActivating(false) is the half that keeps this invisible: it defaults
    -- to TRUE, and left alone a stray click would pull Hammerspoon to the front
    -- and steal focus from whatever is being typed in.
    panel:clickActivating(false)
    panel:mouseCallback(function() end)
    -- Square, not rounded. Rounded corners read as a floating widget; this is
    -- a pane sitting in its own strip, and terminals do not have rounded panes.
    panel[1] = {
      type = "rectangle",
      action = "fill",
      frame = { x = "0%", y = "0%", w = "100%", h = "100%" },
      fillColor = COLORS.bg,
    }
    -- The tmux pane divider, and the only thing separating the panel from
    -- whatever window now ends exactly where it begins.
    panel[2] = {
      type = "rectangle",
      action = "fill",
      frame = { x = 0, y = 0, w = 1, h = "100%" },
      fillColor = COLORS.border,
    }
    panel[3] = {
      type = "text",
      frame = { x = PAD, y = PAD, w = WIDTH - (PAD * 2), h = 100 },
      text = "",
    }
  end

  place()
  local f = panel:frame()
  panel[3].frame = { x = PAD, y = PAD, w = WIDTH - (PAD * 2), h = f.h - (PAD * 2) }
  panel[3].text = styled()
  panel:show()
end

-- ---------------------------------------------------------------------------
-- Collapse / expand
-- ---------------------------------------------------------------------------

-- Hyper+P, claimed through init.lua's extras hook so this file never has to
-- touch the eventtap. Hyper+T stays the triage popup; this is only the drawer.
local function toggle()
  local screen = targetScreen()
  -- Captured BEFORE the claim changes, because reclaim identifies the windows
  -- to move by the frame they currently fill. Read after, every window would
  -- already fail to match and nothing would resize.
  local before = screen and _G.__hsUsableFrame and _G.__hsUsableFrame(screen) or nil

  visible = not visible
  hs.settings.set(SETTING, visible)
  reserve()
  render()

  -- Windows that were filling the old area follow the edge: collapsing gives
  -- the strip back to them, expanding takes it. Guarded because this file also
  -- loads without init.lua (its own test does exactly that).
  if before and _G.__hsReclaim then
    _G.__hsReclaim(screen, before)
  end

  hs.alert.show(visible and "tasks panel" or "tasks panel hidden", 0.7)
end

local pCode = hs.keycodes.map["p"]
if pCode then
  _G.__hsHyperExtras[pCode] = toggle
end

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

-- hs.task rather than hs.execute: this fires on a timer for as long as the
-- machine is up, and blocking Hammerspoon's run loop on a subprocess is how the
-- health checks in init.lua start missing their ticks.
local function refresh()
  if retain.job and retain.job:isRunning() then
    return
  end
  retain.job = hs.task.new(DATA, function(_, stdout, _)
    rows = {}
    local budget = rowBudget()
    -- A count rather than the rows themselves, tallied as they overflow: the
    -- alternative is subtracting #rows afterwards, which stops being true the
    -- moment the "+N more" row below is appended to that same table.
    local hidden = 0
    local function want(row)
      if #rows < budget then
        rows[#rows + 1] = row
      else
        hidden = hidden + 1
      end
    end
    for line in (stdout or ""):gmatch("[^\n]+") do
      local state, text = line:match("^([^\t]*)\t(.*)$")
      if state then
        -- A head row after the first is the next producer's section starting:
        -- give it a blank line first so two producers read as two lists, not
        -- one. Routed through want() like any row — a short screen must still
        -- count it in "+N more" rather than silently overrunning the frame.
        if state == "head" and #rows > 0 then
          want({ state = "blank", text = "" })
        end
        want({ state = state, text = text })
      end
    end
    if hidden > 0 then
      rows[#rows + 1] = { state = "head", text = string.format("+%d more", hidden) }
    end
    render()
  end, DATA_ARGS)
  retain.job:start()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- The cache is normally kept warm by the tmux widget's 5s tick; todoist-panel-data
-- re-fetches it itself when it has gone stale, which is what makes this panel
-- work on a machine with no terminal open.
retain.timer = hs.timer.new(EVERY, refresh)
retain.timer:start()

-- Reposition on monitor attach/detach/rearrange rather than recreating: the
-- canvas survives the change, only its frame is wrong. The claim is re-made
-- too, because it is keyed by screen UUID and the panel may have just fallen
-- back to the built-in display.
retain.screens = hs.screen.watcher.new(function()
  reserve()
  place()
end)
retain.screens:start()

reserve()
refresh()
