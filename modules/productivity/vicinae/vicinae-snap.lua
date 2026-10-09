-- hammerspoon://snap?side=left|right -> snap the frontmost window to that half of
-- its screen, inside the usable area init.lua publishes (so reserved edges are
-- honoured). Fired by the Vicinae "Left Half" / "Right Half" script commands;
-- Vicinae can still be frontmost when they run, so its own windows are skipped.
hs.urlevent.bind("snap", function(_, params)
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isStandard() and win:application():bundleID() ~= "com.vicinaehq.Vicinae" then
      local f = _G.__hsUsableFrame(win:screen())
      f.w = f.w / 2
      if params.side == "right" then
        f.x = f.x + f.w
      end
      win:setFrame(f, 0)
      return
    end
  end
end)
