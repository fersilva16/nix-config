import Data.Char (isSpace, toUpper)
import qualified Data.Map as M
import Data.Maybe (fromJust, isJust)
import Data.Monoid
import Data.Tree
import System.Directory
import System.Exit (exitSuccess)
import System.IO (hPutStrLn)
import XMonad
import XMonad.Actions.CopyWindow (kill1)
import XMonad.Actions.CycleWS (Direction1D (..), WSType (..), moveTo, nextScreen, prevScreen, shiftTo)
import XMonad.Actions.GridSelect
  ( GSConfig
      ( gs_cellheight,
        gs_cellpadding,
        gs_cellwidth,
        gs_font,
        gs_originFractX,
        gs_originFractY
      ),
    bringSelected,
    buildDefaultGSConfig,
    colorRangeFromClassName,
    goToSelected,
    gridselect,
  )
import XMonad.Actions.MouseResize
import XMonad.Actions.Promote
import XMonad.Actions.RotSlaves (rotAllDown, rotSlavesDown)
import qualified XMonad.Actions.Search as S
import XMonad.Actions.WindowGo (runOrRaise)
import XMonad.Actions.WithAll (killAll, sinkAll)
import XMonad.Hooks.DynamicLog (PP (..), dynamicLogWithPP, filterOutWsPP, shorten, wrap, xmobarColor, xmobarPP)
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks (ToggleStruts (..), avoidStruts, docks, manageDocks)
import XMonad.Hooks.ManageHelpers (doCenterFloat, doFullFloat, isFullscreen)
import XMonad.Hooks.ServerMode
import XMonad.Hooks.SetWMName
import XMonad.Hooks.WorkspaceHistory
import XMonad.Layout.Accordion
import XMonad.Layout.GridVariants (Grid (Grid))
import XMonad.Layout.LayoutModifier
import XMonad.Layout.LimitWindows (decreaseLimit, increaseLimit, limitWindows)
import XMonad.Layout.Magnifier hiding (magnify)
import XMonad.Layout.MultiToggle (EOT (EOT), mkToggle, single, (??))
import qualified XMonad.Layout.MultiToggle as MT (Toggle (..))
import XMonad.Layout.MultiToggle.Instances (StdTransformers (MIRROR, NBFULL, NOBORDERS))
import XMonad.Layout.NoBorders
import XMonad.Layout.Renamed
import XMonad.Layout.ResizableTile
import XMonad.Layout.ShowWName
import XMonad.Layout.Simplest
import XMonad.Layout.SimplestFloat
import XMonad.Layout.Spacing
import XMonad.Layout.Spiral
import XMonad.Layout.SubLayouts
import XMonad.Layout.Tabbed
import XMonad.Layout.ThreeColumns
import qualified XMonad.Layout.ToggleLayouts as T (ToggleLayout (Toggle), toggleLayouts)
import XMonad.Layout.WindowArranger (WindowArrangerMsg (..), windowArrange)
import XMonad.Layout.WindowNavigation
import qualified XMonad.StackSet as W
import XMonad.Util.Dmenu
import XMonad.Util.EZConfig (additionalKeysP)
import XMonad.Util.NamedScratchpad
import XMonad.Util.Run (runProcessWithInput, safeSpawn, spawnPipe)
import XMonad.Util.Scratchpad (scratchpadFilterOutWorkspace)
import XMonad.Util.SpawnOnce

colorBack = "#282c34"

colorFore = "#bbc2cf"

color01 = "#1c1f24"

color02 = "#ff6c6b"

color03 = "#98be65"

color04 = "#da8548"

color05 = "#51afef"

color06 = "#c678dd"

color07 = "#5699af"

color08 = "#202328"

color09 = "#5b6268"

color10 = "#da8548"

color11 = "#4db5bd"

color12 = "#ecbe7b"

color13 = "#3071db"

color14 = "#a9a1e1"

color15 = "#46d9ff"

color16 = "#dfdfdf"

colorTrayer :: String
colorTrayer = "--tint 0x282c34"

myFont :: String
myFont = "xft:Caskaydia Cove Nerd Font:regular:size=9:antialias=true:hinting=true"

myModMask :: KeyMask
myModMask = mod4Mask

myTerminal :: String
myTerminal = "kitty"

myBorderWidth :: Dimension
myBorderWidth = 2

myNormColor :: String
myNormColor = colorBack

myFocusColor :: String
myFocusColor = color15

windowCount :: X (Maybe String)
windowCount = gets $ Just . show . length . W.integrate' . W.stack . W.workspace . W.current . windowset

myStartupHook :: X ()
myStartupHook = mempty

myColorizer :: Window -> Bool -> X (String, String)
myColorizer =
  colorRangeFromClassName
    (0x28, 0x2c, 0x34) -- lowest inactive bg
    (0x28, 0x2c, 0x34) -- highest inactive bg
    (0xc7, 0x92, 0xea) -- active bg
    (0xc0, 0xa7, 0x9a) -- inactive fg
    (0x28, 0x2c, 0x34) -- active fg

-- gridSelect menu layout
mygridConfig :: p -> GSConfig Window
mygridConfig colorizer =
  (buildDefaultGSConfig myColorizer)
    { gs_cellheight = 40,
      gs_cellwidth = 200,
      gs_cellpadding = 6,
      gs_originFractX = 0.5,
      gs_originFractY = 0.5,
      gs_font = myFont
    }

spawnSelected' :: [(String, String)] -> X ()
spawnSelected' lst = gridselect conf lst >>= flip whenJust spawn
  where
    conf =
      def
        { gs_cellheight = 40,
          gs_cellwidth = 200,
          gs_cellpadding = 6,
          gs_originFractX = 0.5,
          gs_originFractY = 0.5,
          gs_font = myFont
        }

myScratchPads :: [NamedScratchpad]
myScratchPads =
  [ NS "terminal" spawnTerm findTerm manageTerm,
    NS "ytmdesktop" spawnYtm findYtm manageYtm
  ]
  where
    spawnTerm = myTerminal ++ " --title=scratchpad"
    findTerm = title =? "scratchpad"
    manageTerm = customFloating $ W.RationalRect l t w h
      where
        h = 0.9
        w = 0.9
        t = 0.95 - h
        l = 0.95 - w
    spawnYtm = "ytmdesktop --no-sandbox"
    findYtm = title =? "ytmdesktop"
    manageYtm = customFloating $ W.RationalRect l t w h
      where
        h = 0.9
        w = 0.9
        t = 0.95 - h
        l = 0.95 - w

--Makes setting the spacingRaw simpler to write. The spacingRaw module adds a configurable amount of space around windows.
mySpacing :: Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing i = spacingRaw False (Border i i i i) True (Border i i i i) True

-- Below is a variation of the above except no borders are applied
-- if fewer than two windows. So a single window has no gaps.
mySpacing' :: Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing' i = spacingRaw True (Border i i i i) True (Border i i i i) True

-- Defining a bunch of layouts, many that I don't use.
-- limitWindows n sets maximum number of windows displayed for layout.
-- mySpacing n sets the gap size around the windows.
tall =
  renamed [Replace "tall"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 12 $
              mySpacing 8 $
                ResizableTall 1 (3 / 100) (1 / 2) []

magnify =
  renamed [Replace "magnify"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            magnifier $
              limitWindows 12 $
                mySpacing 8 $
                  ResizableTall 1 (3 / 100) (1 / 2) []

monocle =
  renamed [Replace "monocle"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 20 Full

floats =
  renamed [Replace "floats"] $
    smartBorders $
      limitWindows 20 simplestFloat

grid =
  renamed [Replace "grid"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 12 $
              mySpacing 8 $
                mkToggle (single MIRROR) $
                  Grid (16 / 10)

spirals =
  renamed [Replace "spirals"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            mySpacing' 8 $
              spiral (6 / 7)

threeCol =
  renamed [Replace "threeCol"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 7 $
              ThreeCol 1 (3 / 100) (1 / 2)

threeRow =
  renamed [Replace "threeRow"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 7
            -- Mirror takes a layout and rotates it by 90 degrees.
            -- So we are applying Mirror to the ThreeCol layout.
            $
              Mirror $
                ThreeCol 1 (3 / 100) (1 / 2)

tabs =
  renamed [Replace "tabs"]
  -- I cannot add spacing to this layout because it will
  -- add spacing between window and tabs which looks bad.
  $
    tabbed shrinkText myTabTheme

tallAccordion =
  renamed [Replace "tallAccordion"] Accordion

wideAccordion =
  renamed [Replace "wideAccordion"] $ Mirror Accordion

-- setting colors for tabs layout and tabs sublayout.
myTabTheme =
  def
    { fontName = myFont,
      activeColor = color15,
      inactiveColor = color08,
      activeBorderColor = color15,
      inactiveBorderColor = colorBack,
      activeTextColor = colorBack,
      inactiveTextColor = color16
    }

-- Theme for showWName which prints current workspace when you change workspaces.
myShowWNameTheme :: SWNConfig
myShowWNameTheme =
  def
    { swn_font = "xft:Caskaydia Cove Nerd Font:bold:size=60",
      swn_fade = 1.0,
      swn_bgcolor = "#1c1f24",
      swn_color = "#ffffff"
    }

-- The layout hook
myLayoutHook =
  avoidStruts $
    mouseResize $
      windowArrange $
        T.toggleLayouts floats $
          mkToggle (NBFULL ?? NOBORDERS ?? EOT) myDefaultLayout
  where
    myDefaultLayout =
      withBorder myBorderWidth tall
        ||| magnify
        ||| noBorders monocle
        ||| floats
        ||| noBorders tabs
        ||| grid
        ||| spirals
        ||| threeCol
        ||| threeRow
        ||| tallAccordion
        ||| wideAccordion

myWorkspaces = [" 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " 6 ", " 7 ", " 8 ", " 9 "]

myWorkspaceIndices = M.fromList $ zip myWorkspaces [1 ..]

clickable ws = "<action=xdotool key super+" ++ show i ++ ">" ++ ws ++ "</action>"
  where
    i = fromJust $ M.lookup ws myWorkspaceIndices

myManageHook :: XMonad.Query (Data.Monoid.Endo WindowSet)
myManageHook =
  composeAll
    -- 'doFloat' forces a window to float.  Useful for dialog boxes and such.
    -- using 'doShift ( myWorkspaces !! 7)' sends program to workspace 8!
    -- I'm doing it this way because otherwise I would have to write out the full
    -- name of my workspaces and the names would be very long if using clickable workspaces.
    [ className =? "confirm" --> doFloat,
      className =? "file_progress" --> doFloat,
      className =? "dialog" --> doFloat,
      className =? "download" --> doFloat,
      className =? "error" --> doFloat,
      className =? "Gimp" --> doFloat,
      className =? "notification" --> doFloat,
      className =? "pinentry-gtk-2" --> doFloat,
      className =? "splash" --> doFloat,
      className =? "toolbar" --> doFloat,
      className =? "Yad" --> doCenterFloat,
      title =? "Oracle VM VirtualBox Manager" --> doFloat,
      title =? "Mozilla Firefox" --> doShift (myWorkspaces !! 1),
      className =? "Brave-browser" --> doShift (myWorkspaces !! 1),
      className =? "mpv" --> doShift (myWorkspaces !! 7),
      className =? "Gimp" --> doShift (myWorkspaces !! 8),
      className =? "VirtualBox Manager" --> doShift (myWorkspaces !! 4),
      (className =? "firefox" <&&> resource =? "Dialog") --> doFloat, -- Float Firefox Dialog
      isFullscreen --> doFullFloat
    ]
    <+> namedScratchpadManageHook myScratchPads

-- START_KEYS
myKeys :: [(String, X ())]
myKeys =
  -- KB_GROUP Xmonad
  [ ("M-C-r", spawn "xmonad --recompile"), -- Recompiles xmonad
    ("M-S-r", spawn "xmonad --restart"), -- Restarts xmonad
    ("M-S-q", io exitSuccess), -- Quits xmonad

    -- KB_GROUP Get Help
    -- ("M-S-/", spawn "~/.xmonad/xmonad_keys.sh"), -- Get list of keybindings
    -- ("M-/", spawn "dtos-help"), -- DTOS help/tutorial videos

    -- KB_GROUP Run Prompt
    -- ("M-S-<Return>", spawn "dm-run"), -- Dmenu

    -- KB_GROUP Other Dmenu Prompts
    -- In Xmonad and many tiling window managers, M-p is the default keybinding to
    -- launch dmenu_run, so I've decided to use M-p plus KEY for these dmenu scripts.
    -- ("M-p h", spawn "dm-hub"), -- allows access to all dmscripts
    -- ("M-p a", spawn "dm-sounds"), -- choose an ambient background
    -- ("M-p b", spawn "dm-setbg"), -- set a background
    -- ("M-p c", spawn "dtos-colorscheme"), -- choose a colorscheme
    -- ("M-p C", spawn "dm-colpick"), -- pick color from our scheme
    -- ("M-p e", spawn "dm-confedit"), -- edit config files
    -- ("M-p i", spawn "dm-maim"), -- screenshots (images)
    -- ("M-p k", spawn "dm-kill"), -- kill processes
    -- ("M-p m", spawn "dm-man"), -- manpages
    -- ("M-p n", spawn "dm-note"), -- store one-line notes and copy them
    -- ("M-p o", spawn "dm-bookman"), -- qutebrowser bookmarks/history
    -- ("M-p p", spawn "passmenu -p \"Pass: \""), -- passmenu
    -- ("M-p q", spawn "dm-logout"), -- logout menu
    -- ("M-p r", spawn "dm-radio"), -- online radio
    -- ("M-p s", spawn "dm-websearch"), -- search various search engines
    -- ("M-p t", spawn "dm-translate"), -- translate text (Google Translate)

    -- KB_GROUP Useful programs to have a keybinding for launch
    ("M-<Return>", spawn myTerminal),
    -- ("M-M1-h", spawn (myTerminal ++ " -e htop")),
    -- KB_GROUP Kill windows
    ("M-S-c", kill1), -- Kill the currently focused client
    ("M-S-a", killAll), -- Kill all windows on current workspace

    -- KB_GROUP Workspaces
    ("M-.", nextScreen), -- Switch focus to next monitor
    ("M-,", prevScreen), -- Switch focus to prev monitor
    ("M-S-<KP_Add>", shiftTo Next nonNSP >> moveTo Next nonNSP), -- Shifts focused window to next ws
    ("M-S-<KP_Subtract>", shiftTo Prev nonNSP >> moveTo Prev nonNSP), -- Shifts focused window to prev ws

    -- KB_GROUP Floating windows
    ("M-f", sendMessage (T.Toggle "floats")), -- Toggles my 'floats' layout
    ("M-t", withFocused $ windows . W.sink), -- Push floating window back to tile
    ("M-S-t", sinkAll), -- Push ALL floating windows to tile

    -- KB_GROUP Increase/decrease spacing (gaps)
    ("C-M1-j", decWindowSpacing 4), -- Decrease window spacing
    ("C-M1-k", incWindowSpacing 4), -- Increase window spacing
    ("C-M1-h", decScreenSpacing 4), -- Decrease screen spacing
    ("C-M1-l", incScreenSpacing 4), -- Increase screen spacing

    -- KB_GROUP Grid Select (CTR-g followed by a key)
    ("C-g t", goToSelected $ mygridConfig myColorizer), -- goto selected window
    ("C-g b", bringSelected $ mygridConfig myColorizer), -- bring selected window

    -- KB_GROUP Windows navigation
    ("M-m", windows W.focusMaster), -- Move focus to the master window
    ("M-j", windows W.focusDown), -- Move focus to the next window
    ("M-k", windows W.focusUp), -- Move focus to the prev window
    ("M-S-m", windows W.swapMaster), -- Swap the focused window and the master window
    ("M-S-j", windows W.swapDown), -- Swap focused window with next window
    ("M-S-k", windows W.swapUp), -- Swap focused window with prev window
    ("M-<Backspace>", promote), -- Moves focused window to master, others maintain order
    ("M-S-<Tab>", rotSlavesDown), -- Rotate all windows except master and keep focus in place
    ("M-C-<Tab>", rotAllDown), -- Rotate all the windows in the current stack

    -- KB_GROUP Layouts
    ("M-<Tab>", sendMessage NextLayout), -- Switch to next layout
    ("M-<Space>", sendMessage (MT.Toggle NBFULL) >> sendMessage ToggleStruts), -- Toggles noborder/full

    -- KB_GROUP Increase/decrease windows in the master pane or the stack
    ("M-S-<Up>", sendMessage (IncMasterN 1)), -- Increase # of clients master pane
    ("M-S-<Down>", sendMessage (IncMasterN (-1))), -- Decrease # of clients master pane
    ("M-C-<Up>", increaseLimit), -- Increase # of windows
    ("M-C-<Down>", decreaseLimit), -- Decrease # of windows

    -- KB_GROUP Window resizing
    ("M-h", sendMessage Shrink), -- Shrink horiz window width
    ("M-l", sendMessage Expand), -- Expand horiz window width
    ("M-M1-j", sendMessage MirrorShrink), -- Shrink vert window width
    ("M-M1-k", sendMessage MirrorExpand), -- Expand vert window width

    -- KB_GROUP Sublayouts
    -- This is used to push windows to tabbed sublayouts, or pull them out of it.
    ("M-C-h", sendMessage $ pullGroup L),
    ("M-C-l", sendMessage $ pullGroup R),
    ("M-C-k", sendMessage $ pullGroup U),
    ("M-C-j", sendMessage $ pullGroup D),
    ("M-C-m", withFocused (sendMessage . MergeAll)),
    -- , ("M-C-u", withFocused (sendMessage . UnMerge))
    ("M-C-/", withFocused (sendMessage . UnMergeAll)),
    ("M-C-.", onGroup W.focusUp'), -- Switch focus to next tab
    ("M-C-,", onGroup W.focusDown'), -- Switch focus to prev tab

    -- KB_GROUP Scratchpads
    -- Toggle show/hide these programs.  They run on a hidden workspace.
    -- When you toggle them to show, it brings them to your current workspace.
    -- Toggle them to hide and it sends them back to hidden workspace (NSP).
    ("M-s t", namedScratchpadAction myScratchPads "terminal"),
    ("M-s y", namedScratchpadAction myScratchPads "ytmdesktop"),
    -- ("<XF86AudioPlay>", spawn "mocp --play"),
    -- ("<XF86AudioPrev>", spawn "mocp --previous"),
    -- ("<XF86AudioNext>", spawn "mocp --next"),
    ("<XF86AudioMute>", spawn "amixer set Master toggle"),
    ("<XF86AudioLowerVolume>", spawn "amixer set Master 5%- unmute"),
    ("<XF86AudioRaiseVolume>", spawn "amixer set Master 5%+ unmute"),
    ("<Print>", spawn "flameshot gui")
    -- ("<XF86HomePage>", spawn "qutebrowser https://www.youtube.com/c/DistroTube"),
    -- ("<XF86Search>", spawn "dm-websearch"),
    -- ("<XF86Mail>", runOrRaise "thunderbird" (resource =? "thunderbird")),
    -- ("<XF86Calculator>", runOrRaise "qalculate-gtk" (resource =? "qalculate-gtk")),
    --  ("<XF86Eject>", spawn "toggleeject"),
    -- ("<Print>", spawn "dm-maim")
  ]
  where
    -- The following lines are needed for named scratchpads.
    nonNSP = WSIs (return (\ws -> W.tag ws /= "NSP"))
    nonEmptyNonNSP = WSIs (return (\ws -> isJust (W.stack ws) && W.tag ws /= "NSP"))

-- END_KEYS

main :: IO ()
main = do
  -- Launching three instances of xmobar on their monitors.
  xmproc0 <- spawnPipe "xmobar -x 0 $HOME/.config/xmobar/.xmobarrc"
  xmproc1 <- spawnPipe "xmobar -x 1 $HOME/.config/xmobar/.xmobarrc"
  -- the xmonad, ya know...what the WM is named after!
  xmonad . ewmh . docks $
    def
      { manageHook = myManageHook <+> manageDocks,
        modMask = myModMask,
        terminal = myTerminal,
        startupHook = myStartupHook,
        layoutHook = showWName' myShowWNameTheme myLayoutHook,
        workspaces = myWorkspaces,
        borderWidth = myBorderWidth,
        normalBorderColor = myNormColor,
        focusedBorderColor = myFocusColor,
        logHook =
          dynamicLogWithPP $
            filterOutWsPP [scratchpadWorkspaceTag] $
              xmobarPP
                { ppOutput = \x ->
                    hPutStrLn xmproc0 x
                      >> hPutStrLn xmproc1 x,
                  ppCurrent =
                    xmobarColor color06 ""
                      . wrap
                        ("<box type=Bottom width=2 mb=2 color=" ++ color06 ++ ">")
                        "</box>",
                  ppVisible = xmobarColor color06 "" . clickable,
                  ppHidden =
                    xmobarColor color05 ""
                      . wrap
                        ("<box type=Top width=2 mt=2 color=" ++ color05 ++ ">")
                        "</box>"
                      . clickable,
                  ppHiddenNoWindows = xmobarColor color05 "" . clickable,
                  ppTitle = xmobarColor color16 "" . shorten 60,
                  ppSep = "<fc=" ++ color09 ++ "> <fn=1>|</fn> </fc>",
                  ppUrgent = xmobarColor color02 "" . wrap "!" "!",
                  ppExtras = [windowCount],
                  ppOrder = \(ws : l : t : ex) -> [ws, l] ++ ex ++ [t]
                }
      }
      `additionalKeysP` myKeys
