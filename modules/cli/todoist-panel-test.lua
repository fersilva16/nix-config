-- Self-check for todoist-panel.lua, run by `nix flake check`.
--
-- The panel cannot be exercised on the machine it runs on without a live
-- Hammerspoon, a live Todoist token and a monitor, so the parts worth
-- protecting — the TSV parse, the row cap, the show/hide edges and the colour
-- routing — are driven here against a stub `hs`. Everything below is an assert;
-- there is no framework and nothing to install.
--
-- Locally:  nvim -l modules/cli/todoist-panel-test.lua
-- In CI:    nix flake check   (runs it under luajit against the INSTALLED file,
--                              prelude and all, so the nix-generated config
--                              header is covered too)
--
-- Lua 5.1 / luajit compatible on purpose — that is what the flake check uses.

local PANEL = os.getenv("PANEL") or "modules/cli/todoist-panel.lua"

-- ---------------------------------------------------------------------------
-- Stub hs
-- ---------------------------------------------------------------------------
local captured, calls

-- Every frame the panel handed to __hsReclaim, in order.
local reclaims = {}

local function reset()
  captured = {}
  calls = { show = 0, hide = 0, frames = {} }
  reclaims = {}
end

local canvas = setmetatable({}, {
  __index = function(t, k)
    if k == "level" or k == "behavior" then
      return function(s)
        return s
      end
    end
    if k == "show" then
      return function(s)
        calls.show = calls.show + 1
        return s
      end
    end
    if k == "hide" then
      return function(s)
        calls.hide = calls.hide + 1
        return s
      end
    end
    if k == "frame" then
      return function(s, f)
        if f then
          calls.frames[#calls.frames + 1] = f
          rawset(t, "_f", f)
          return s
        end
        return rawget(t, "_f") or { x = 0, y = 0, w = 300, h = 200 }
      end
    end
    return rawget(t, k)
  end,
})

local SCREEN = { x = 0, y = 25, w = 1920, h = 1055 }
local stdout = ""
-- Stands in for hs.settings' on-disk store, which is what has to survive the
-- reload-on-wake that a plain local would not.
local SETTINGS = {}

local styledMT
styledMT = {
  __concat = function(a, b)
    return setmetatable({ s = (a.s or "") .. (b.s or "") }, styledMT)
  end,
}

hs = {
  canvas = {
    new = function()
      return canvas
    end,
    windowLevels = { floating = 5 },
  },
  styledtext = {
    new = function(s, attrs)
      local o = setmetatable({
        s = s,
        color = attrs and attrs.color,
        font = attrs and attrs.font,
      }, styledMT)
      captured[#captured + 1] = o
      return o
    end,
  },
  alert = {
    show = function() end,
  },
  keycodes = { map = { p = 35 } },
  settings = {
    get = function(k)
      return SETTINGS[k]
    end,
    set = function(k, v)
      SETTINGS[k] = v
    end,
  },
  screen = {
    find = function()
      return nil
    end,
    primaryScreen = function()
      return {
        frame = function()
          return SCREEN
        end,
        getUUID = function()
          return "SCREEN-UUID"
        end,
      }
    end,
    watcher = {
      new = function(fn)
        return {
          fn = fn,
          start = function(s)
            return s
          end,
        }
      end,
    },
  },
  timer = {
    new = function(_, fn)
      return {
        fn = fn,
        start = function(s)
          return s
        end,
      }
    end,
  },
  task = {
    new = function(_, cb)
      return {
        start = function(s)
          cb(0, stdout, "")
          return s
        end,
        isRunning = function()
          return false
        end,
      }
    end,
  },
}

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------
local function load_with(out)
  stdout = out
  reset()
  rawset(canvas, "_f", nil)
  -- Cleared per load the way init.lua clears them on every hs.reload().
  _G.__hsReserved = {}
  _G.__hsHyperExtras = {}

  -- Mirrors init.lua's usableFrame closely enough to check the contract the
  -- panel depends on: that a right-edge claim narrows the usable area, and that
  -- reclaim is handed the frame as it was BEFORE the claim changed.
  _G.__hsUsableFrame = function()
    local f = { x = SCREEN.x, y = SCREEN.y, w = SCREEN.w, h = SCREEN.h }
    for _, r in pairs(_G.__hsReserved) do
      if r.screen == "SCREEN-UUID" and r.edge == "right" then
        f.w = f.w - r.size
      end
    end
    return f
  end
  _G.__hsReclaim = function(_, oldFrame)
    reclaims[#reclaims + 1] = oldFrame
  end

  dofile(PANEL)
end

-- Hyper+P, reached the way the eventtap reaches it.
local function pressToggle()
  reset()
  _G.__hsHyperExtras[35]()
end

local function claim()
  return _G.__hsReserved.todoistPanel
end

-- Re-fires the already-loaded instance, the way the refresh timer does. This is
-- the only way to reach the transitions (list emptying, list coming back),
-- which a fresh dofile can never show.
local function tick(out)
  stdout = out
  reset()
  _G.__todoistPanelRetain.timer.fn()
end

local function text()
  local s = ""
  for _, c in ipairs(captured) do
    s = s .. c.s
  end
  return s
end

local function lastFrame()
  return calls.frames[#calls.frames]
end

local function rowsOf(n, state)
  local t = {}
  for i = 1, n do
    t[i] = (state or "normal") .. "\ttask " .. i
  end
  return table.concat(t, "\n")
end

-- Drives the SCREEN rather than overriding maxTasks. The installed file carries
-- a nix-generated `_G.__todoistPanelCfg` prelude that reassigns maxTasks on
-- every load, so a test that set it would pass locally against the bare source
-- and prove nothing about the file actually shipped.
local function withScreen(h, fn)
  local saved = SCREEN
  SCREEN = { x = 0, y = 25, w = 1440, h = h }
  local okRun, err = pcall(fn)
  SCREEN = saved
  if not okRun then
    error(err, 0)
  end
end

-- Read back the config the panel actually loaded, so this file keeps passing
-- when the nix options change rather than pinning yesterday's numbers.
load_with(rowsOf(1))
local cfg = _G.__todoistPanelCfg or {}
local WIDTH = cfg.width or 300
local MAX = cfg.maxTasks or 12

-- The panel is full-height now, so its frame says nothing about how many rows
-- it drew. Everything below counts STYLED RUNS instead: one per row it was
-- handed, head rows included, plus the "+N more" line when it overflows. That
-- is the thing actually worth asserting, and it does not move when padding
-- does.
local function drawnRows()
  return #captured
end

local function rowText(i)
  return captured[i].s
end

-- ---------------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------------
local ok = 0
local function check(name, fn)
  -- Per-check, because hs.settings is persistent by design: a check that
  -- collapses the panel would otherwise leave every later check running against
  -- a collapsed one, which passes vacuously instead of failing.
  SETTINGS = {}
  fn()
  ok = ok + 1
  print(string.format("ok %d - %s", ok, name))
end

check("docks flush to the right edge, below the menu bar", function()
  load_with(rowsOf(7))
  local f = lastFrame()
  assert(calls.show == 1, "panel should be shown")
  assert(f.x == SCREEN.x + SCREEN.w - WIDTH, "x should be right-docked, got " .. f.x)
  assert(f.y == SCREEN.y, "y should clear the menu bar, got " .. f.y)
  assert(f.w == WIDTH, "width should match config, got " .. f.w)
  assert(f.h == SCREEN.h, "panel should span the full usable height, got " .. f.h)
  assert(drawnRows() == 7, "should draw 7 rows, drew " .. drawnRows())
end)

-- The count moved into the producers, because each one owns the definition its
-- number is of: todoist-panel-data reads the same cache and the same today/sort
-- rules as the tmux widget, so the two cannot disagree. A total summed here
-- would have started counting linear issues as things "due today" the moment a
-- second producer appeared. What this file still has to guarantee is that the
-- panel passes head rows through untouched instead of recomputing them.
check("producer head rows are drawn verbatim, not recomputed", function()
  load_with("head\t\239\130\174  20 today\nnormal\ttask 1\n")
  assert(rowText(1):find("20 today", 1, true), "head row should survive intact: " .. rowText(1))
  -- U+F0AE nf-fa-tasks, as UTF-8 bytes: the glyph the tmux widget prints, and
  -- the reason head rows must reach the canvas byte-for-byte.
  assert(rowText(1):find("\239\130\174", 1, true), "the tasks glyph should survive the parse")
  assert(drawnRows() == 2, "head row plus its task, drew " .. drawnRows())
end)

check("emptying the list keeps the pane and says so", function()
  load_with(rowsOf(3))
  tick("")
  assert(calls.hide == 0, "an expanded pane must not vanish; the strip is still reserved")
  assert(calls.show == 1, "it should redraw")
  assert(text():find("nothing due", 1, true), "should say the list is clear")
end)

check("tasks coming back re-show it without a reload", function()
  load_with(rowsOf(3))
  tick("")
  tick(rowsOf(2))
  assert(calls.show == 1, "should be shown again")
  assert(drawnRows() == 2, "should draw the 2 new rows, drew " .. drawnRows())
end)

-- Reached only when NO producer said anything at all: every producer prints its
-- own head row unconditionally, so this is the failed-fetch / nothing-installed
-- case, and the reserved strip still must not be left looking broken.
check("cold start with no producer output still draws the pane", function()
  load_with("")
  assert(calls.show == 1, "the reserved strip must not be left empty")
  assert(text():find("nothing due", 1, true), "should show the clear state")
end)

-- One pane, one row budget, however many producers. The failure this rules out
-- is each section getting its own cap and the total running off the bottom of
-- the screen, where the rows cannot be read and are not counted either.
check("two producers share one pane, one budget and one +N more", function()
  withScreen(4000, function()
    load_with(
      "head\tlinear  2 active\nnormal\tENG-1  a\nnormal\tENG-2  b\n"
        .. "head\t\239\130\174  20 today\n"
        .. rowsOf(MAX)
    )
    local t = text()
    assert(t:find("linear  2 active", 1, true), "the linear section should be drawn")
    assert(t:find("20 today", 1, true), "the todoist section should be drawn")
    assert(drawnRows() == MAX + 1, "budget is shared across sections, drew " .. drawnRows())
    assert(t:find("%+5 more"), "overflow across both sections must be counted, got:\n" .. t)
    -- The separator itself: a blank line, costing a budget slot like any row,
    -- between the last linear row and the second section's head.
    assert(rowText(4) == "\n", "row 4 should be the blank separator, got " .. rowText(4))
    assert(rowText(5):find("20 today", 1, true), "row 5 should be the todoist head, got " .. rowText(5))
  end)
end)

check("overflow collapses into a +N more row", function()
  load_with(rowsOf(MAX + 8))
  local t = text()
  assert(t:find("%+8 more"), "expected '+8 more', got:\n" .. t)
  assert(t:find("task " .. MAX, 1, true), "row " .. MAX .. " should be present")
  assert(not t:find("task " .. (MAX + 1), 1, true), "row " .. (MAX + 1) .. " should be capped out")
  assert(drawnRows() == MAX + 1, "should draw maxTasks rows plus the +N line, drew " .. drawnRows())
end)

-- The regression these two exist for: at the default maxTasks the panel is far
-- shorter than any normal screen, so a broken bound stays invisible until
-- someone raises the option or docks to a small display.
check("a screen too short for maxTasks rows still fits, and says so", function()
  withScreen(200, function()
    load_with(rowsOf(500))
    local f = lastFrame()
    assert(f.h == 200, "panel should still be exactly full height, got " .. f.h)
    -- Stated as a comparison against the roomy case rather than against a row
    -- height copied from the panel: if the budget ignored screen height, this
    -- short pane would draw the same maxTasks rows as a 4000pt one and run them
    -- straight off the bottom, where they cannot be read.
    assert(
      drawnRows() < MAX + 1,
      "a 200pt pane drew " .. drawnRows() .. " rows, same as a tall one -- they overflow"
    )
    assert(text():find("%+%d+ more"), "rows dropped for space must still be counted")
  end)
end)

check("a screen with room to spare is bounded by maxTasks", function()
  withScreen(4000, function()
    load_with(rowsOf(500))
    assert(
      drawnRows() == MAX + 1,
      "should stop at maxTasks(" .. MAX .. ") + the +N row, drew " .. drawnRows()
    )
  end)
end)

-- Relationships, not thresholds: "red is redder than it is green" survives a
-- palette tweak, where "red > 0.8" turns every theme change into a failure.
local function isRed(c)
  return c.red > c.green * 2 and c.red > c.blue * 2
end
local function isAmber(c)
  return c.red > 0.5 and c.green > 0.4 and c.blue < 0.2
end
-- The panel draws on Flexoki paper, so body text has to be the dark end.
local function readsOnPaper(c)
  return (c.red + c.green + c.blue) / 3 < 0.4
end

check("state routes to a colour; overdue and urgent are red", function()
  load_with("overdue\tslipped\nurgent\tp1\nmedium\tp2\nnormal\tplain\n")
  local overdue, urgent, medium, normal = captured[1], captured[2], captured[3], captured[4]
  assert(isRed(overdue.color), "overdue should be red")
  assert(isRed(urgent.color), "urgent should be red")
  assert(isAmber(medium.color), "medium should be amber")
  assert(readsOnPaper(normal.color), "normal must be dark enough to read on the paper background")
end)

check("every row colour is legible on the panel background", function()
  load_with("overdue\ta\nurgent\tb\nmedium\tc\nnormal\td\n")
  for i = 1, 4 do
    local c = captured[i].color
    -- Flexoki paper is ~0.93 luminance; anything near it vanishes.
    assert(
      (c.red + c.green + c.blue) / 3 < 0.75,
      "row " .. i .. " is too light to read on #F2F0E5"
    )
  end
end)

check("an unrecognised state falls back to the normal colour", function()
  load_with("banana\tsomething\n")
  assert(calls.show == 1, "should still render")
  assert(captured[1].color ~= nil, "should not render colourless")
end)

check("task text containing spaces and non-ascii survives the split", function()
  load_with("normal\tBuy tickets to São Paulo — Sept 7 to 19\n")
  assert(text():find("São Paulo", 1, true), "text should round-trip intact")
end)

check("blank and malformed lines are skipped, not drawn", function()
  load_with("normal\tgood\n\nnotabhere\n\nmedium\talso good\n")
  assert(drawnRows() == 2, "only well-formed rows should be drawn, drew " .. drawnRows())
  assert(not text():find("notabhere", 1, true), "a line with no tab is not a row")
end)

check("long-lived objects are retained against GC", function()
  load_with(rowsOf(1))
  local r = _G.__todoistPanelRetain
  assert(r and r.timer, "refresh timer must be retained or it silently stops")
  assert(r.screens, "screen watcher must be retained or it silently stops")
end)

check("screen watcher repositions without recreating the canvas", function()
  load_with(rowsOf(4))
  local before = calls.show
  SCREEN = { x = 0, y = 25, w = 3840, h = 2000 }
  _G.__todoistPanelRetain.screens.fn()
  assert(lastFrame().x == 3840 - WIDTH, "should re-dock to the new screen width")
  assert(calls.show == before, "repositioning should not re-show/recreate")
  SCREEN = { x = 0, y = 25, w = 1920, h = 1055 }
end)

-- ---------------------------------------------------------------------------
-- Collapse / expand + the reserved edge
-- ---------------------------------------------------------------------------

check("claims a right-edge reservation on the panel's screen when shown", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  local c = claim()
  assert(c, "should claim an edge")
  assert(c.edge == "right" and c.size == WIDTH, "bad claim: " .. c.edge .. "/" .. c.size)
  assert(c.screen == "SCREEN-UUID", "claim must be keyed by screen UUID, got " .. tostring(c.screen))
end)

check("Hyper+P collapses: panel hides and the edge is released", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  pressToggle()
  assert(calls.hide == 1, "panel should hide")
  assert(claim() == nil, "reservation must be released so windows reclaim the strip")
end)

check("Hyper+P again expands: panel returns and reclaims the edge", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  pressToggle()
  pressToggle()
  assert(calls.show == 1, "panel should come back")
  assert(claim() ~= nil, "reservation must be reclaimed")
end)

-- The regression that makes "collapsible" real: init.lua runs a full
-- hs.reload() on systemDidWake and screensDidUnlock, so a plain in-memory flag
-- would put the panel back on screen every single time the lid opens.
check("collapsed survives a reload (lid close / wake)", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  pressToggle()
  load_with(rowsOf(3))
  assert(calls.show == 0, "panel must stay collapsed across a reload")
  assert(claim() == nil, "and must not silently re-claim the edge")
end)

check("expanded also survives a reload", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  pressToggle()
  pressToggle()
  load_with(rowsOf(3))
  assert(calls.show == 1, "panel must come back expanded")
  assert(claim() ~= nil, "and re-claim the edge")
end)

check("the claim holds at zero tasks, so windows do not resize all day", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  tick("")
  assert(calls.hide == 0, "the pane stays up")
  assert(claim() ~= nil, "but the strip stays reserved while toggled on")
end)

check("collapsed stays collapsed when new tasks arrive", function()
  SETTINGS = {}
  load_with(rowsOf(1))
  pressToggle()
  tick(rowsOf(9))
  assert(calls.show == 0, "a new task must not pop the drawer back open")
end)

-- ---------------------------------------------------------------------------
-- Looks like the terminal
-- ---------------------------------------------------------------------------

check("background is solid and square, not a translucent rounded widget", function()
  load_with(rowsOf(2))
  local bg = rawget(canvas, 1)
  assert(bg and bg.type == "rectangle", "element 1 should be the background")
  assert(
    (bg.fillColor.alpha or 1) == 1,
    "background must be opaque, got alpha " .. tostring(bg.fillColor.alpha)
  )
  assert(bg.roundedRectRadii == nil, "a terminal pane has square corners")
end)

check("every line uses the terminal's own monospace font", function()
  load_with(rowsOf(2))
  -- Without this the loop below runs zero times and passes while proving
  -- nothing, which is exactly how it first "passed".
  assert(#captured == 2, "expected 2 styled runs, got " .. #captured)
  for i = 1, #captured do
    local f = captured[i].font
    assert(f and f.name, "line " .. i .. " has no font set")
    assert(
      f.name:find("Caskaydia"),
      "line " .. i .. " should use Ghostty's font, got " .. f.name
    )
  end
end)

-- ---------------------------------------------------------------------------
-- Windows follow the edge
-- ---------------------------------------------------------------------------

-- The ordering bug this pins: reclaim identifies windows to move by the frame
-- they currently fill, so it must be handed the usable frame from BEFORE the
-- claim changed. Read it after and every window fails to match, the reclaim
-- silently moves nothing, and the panel just overlaps again.
check("collapsing hands reclaim the NARROW frame, so windows grow into the strip", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  pressToggle()
  assert(#reclaims == 1, "reclaim should run exactly once, ran " .. #reclaims)
  assert(
    reclaims[1].w == SCREEN.w - WIDTH,
    "must pass the pre-collapse (narrow) frame, got w=" .. reclaims[1].w
  )
end)

check("expanding hands reclaim the FULL frame, so windows shrink out of it", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  pressToggle()
  pressToggle()
  assert(#reclaims == 1, "reclaim should run once per toggle")
  assert(
    reclaims[1].w == SCREEN.w,
    "must pass the pre-expand (full) frame, got w=" .. reclaims[1].w
  )
end)

check("the claimed size matches what the panel actually draws", function()
  SETTINGS = {}
  load_with(rowsOf(3))
  local drawn = lastFrame()
  assert(
    claim().size == drawn.w,
    "a strip reserved wider or narrower than the panel leaves a gap: claim="
      .. claim().size
      .. " drawn="
      .. drawn.w
  )
  assert(
    drawn.x + drawn.w == SCREEN.x + SCREEN.w,
    "the panel must sit flush against the screen edge it reserved"
  )
end)

print(string.format("\nall %d checks passed", ok))
