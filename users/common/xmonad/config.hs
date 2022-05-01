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

myFont :: String
myFont = "xft:FiraCode Nerd Font:regular:size=9:antialias=true:hinting=true"

myModMask :: KeyMask
myModMask = mod4Mask

myTerminal :: String
myTerminal = "kitty"

myBorderWidth :: Dimension
myBorderWidth = 2

myNormColor :: String
myNormColor = "%bg%"

myFocusColor :: String
myFocusColor = "%cyan%"

windowCount :: X (Maybe String)
windowCount = gets $ Just . show . length . W.integrate' . W.stack . W.workspace . W.current . windowset

myStartupHook :: X ()
myStartupHook = mempty

myColorizer :: Window -> Bool -> X (String, String)
myColorizer =
  colorRangeFromClassName
    (0x28, 0x2c, 0x34)
    (0x28, 0x2c, 0x34)
    (0xc7, 0x92, 0xea)
    (0xc0, 0xa7, 0x9a)
    (0x28, 0x2c, 0x34)

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

myScratchPadFloat = customFloating $ W.RationalRect l t w h
  where
    h = 0.9
    w = 0.9
    t = 0.95 - h
    l = 0.95 - w

myScratchPads :: [NamedScratchpad]
myScratchPads =
  [ NS "terminal" spawnTerm findTerm manageTerm,
    NS "music" spawnMusic findMusic manageMusic
  ]
  where
    spawnTerm = myTerminal ++ " --title=scratchpad"
    findTerm = title =? "scratchpad"
    manageTerm = myScratchPadFloat

    spawnMusic = "ytmdesktop --no-sandbox"
    findMusic = className =? "youtube-music-desktop-app"
    manageMusic = myScratchPadFloat

mySpacing :: Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing i = spacingRaw False (Border i i i i) True (Border i i i i) True

tall =
  renamed [Replace "tall"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 12 $
              mySpacing 8 $
                ResizableTall 1 (3 / 100) (1 / 2) []

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

tabs =
  renamed [Replace "tabs"] $
    tabbed shrinkText myTabTheme

myTabTheme =
  def
    { fontName = myFont,
      activeColor = "%cyan%",
      inactiveColor = "%base2%",
      activeBorderColor = "%cyan%",
      inactiveBorderColor = "%bg%",
      activeTextColor = "%bg%",
      inactiveTextColor = "%base8%"
    }

myShowWNameTheme :: SWNConfig
myShowWNameTheme =
  def
    { swn_font = "xft:FiraCode Nerd Font:bold:size=60",
      swn_fade = 1.0,
      swn_bgcolor = "%bg%",
      swn_color = "%fg%"
    }

myLayoutHook =
  avoidStruts $
    mouseResize $
      windowArrange $
        mkToggle (NBFULL ?? NOBORDERS ?? EOT) myDefaultLayout
  where
    myDefaultLayout =
      withBorder myBorderWidth tall
        ||| noBorders tabs
        ||| grid

myWorkspaces = [" 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " 6 ", " 7 ", " 8 ", " 9 "]

myWorkspaceIndices = M.fromList $ zip myWorkspaces [1 ..]

clickable ws = "<action=xdotool key super+" ++ show i ++ ">" ++ ws ++ "</action>"
  where
    i = fromJust $ M.lookup ws myWorkspaceIndices

myManageHook :: XMonad.Query (Data.Monoid.Endo WindowSet)
myManageHook =
  composeAll
    [ className =? "discord" --> doShift (myWorkspaces !! 8),
      className =? "Slack" --> doShift (myWorkspaces !! 8),
      isFullscreen --> doFullFloat
    ]
    <+> namedScratchpadManageHook myScratchPads

myKeys :: [(String, X ())]
myKeys =
  [ ("M-S-r", spawn "xmonad --restart"),
    ("M-S-q", io exitSuccess),
    ("M-<Return>", spawn myTerminal),
    ("M-S-c", kill1),
    ("M-S-a", killAll),
    ("M-.", nextScreen),
    ("M-,", prevScreen),
    ("M-S-<KP_Add>", shiftTo Next nonNSP >> moveTo Next nonNSP),
    ("M-S-<KP_Subtract>", shiftTo Prev nonNSP >> moveTo Prev nonNSP),
    ("M-f", sendMessage (T.Toggle "floats")),
    ("M-t", withFocused $ windows . W.sink),
    ("M-S-t", sinkAll),
    ("M-m", windows W.focusMaster),
    ("M-j", windows W.focusDown),
    ("M-k", windows W.focusUp),
    ("M-S-m", windows W.swapMaster),
    ("M-S-j", windows W.swapDown),
    ("M-S-k", windows W.swapUp),
    ("M-<Backspace>", promote),
    ("M-S-<Tab>", rotSlavesDown),
    ("M-C-<Tab>", rotAllDown),
    ("M-<Tab>", sendMessage NextLayout),
    ("M-<Space>", sendMessage (MT.Toggle NBFULL) >> sendMessage ToggleStruts),
    ("M-S-<Up>", sendMessage (IncMasterN 1)),
    ("M-S-<Down>", sendMessage (IncMasterN (-1))),
    ("M-C-<Up>", increaseLimit),
    ("M-C-<Down>", decreaseLimit),
    ("M-h", sendMessage Shrink),
    ("M-l", sendMessage Expand),
    ("M-M1-j", sendMessage MirrorShrink),
    ("M-M1-k", sendMessage MirrorExpand),
    ("M-C-h", sendMessage $ pullGroup L),
    ("M-C-l", sendMessage $ pullGroup R),
    ("M-C-k", sendMessage $ pullGroup U),
    ("M-C-j", sendMessage $ pullGroup D),
    ("M-C-m", withFocused (sendMessage . MergeAll)),
    ("M-C-u", withFocused (sendMessage . UnMerge)),
    ("M-C-/", withFocused (sendMessage . UnMergeAll)),
    ("M-C-.", onGroup W.focusUp'),
    ("M-C-,", onGroup W.focusDown'),
    ("M-C-S-t", namedScratchpadAction myScratchPads "terminal"),
    ("M-C-S-m", namedScratchpadAction myScratchPads "music"),
    ("<XF86AudioMute>", spawn "amixer set Master toggle"),
    ("<XF86AudioLowerVolume>", spawn "amixer set Master 2%- unmute"),
    ("<XF86AudioRaiseVolume>", spawn "amixer set Master 2%+ unmute"),
    ("<Print>", spawn "flameshot gui")
  ]
  where
    nonNSP = WSIs (return (\ws -> W.tag ws /= "NSP"))
    nonEmptyNonNSP = WSIs (return (\ws -> isJust (W.stack ws) && W.tag ws /= "NSP"))

main :: IO ()
main = do
  xmproc0 <- spawnPipe "xmobar -x 0 $HOME/.config/xmobar/.xmobarrc"
  xmproc1 <- spawnPipe "xmobar -x 1 $HOME/.config/xmobar/.xmobarrc"
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
                    xmobarColor "%magenta%" ""
                      . wrap
                        ("<box type=Bottom width=2 mb=2 color=" ++ "%magenta%" ++ ">")
                        "</box>",
                  ppVisible = xmobarColor "%magenta%" "" . clickable,
                  ppHidden =
                    xmobarColor "%blue%" ""
                      . wrap
                        ("<box type=Top width=2 mt=2 color=" ++ "%blue%" ++ ">")
                        "</box>"
                      . clickable,
                  ppHiddenNoWindows = xmobarColor "%blue%" "" . clickable,
                  ppTitle = xmobarColor "%base8%" "" . shorten 60,
                  ppSep = "<fc=" ++ "%base5%" ++ ">  |  </fc>",
                  ppUrgent = xmobarColor "%red%" "" . wrap "!" "!",
                  ppExtras = [windowCount],
                  ppOrder = \(ws : l : t : ex) -> [ws, l] ++ ex ++ [t]
                }
      }
      `additionalKeysP` myKeys
