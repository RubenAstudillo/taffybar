-----------------------------------------------------------------------------
-- |
-- Module      : System.Taffybar.Windows
-- Copyright   : (c) José A. Romero L.
-- License     : BSD3-style (see LICENSE)
--
-- Maintainer  : Ivan Malison <IvanMalison@gmail.com>
-- Stability   : unstable
-- Portability : unportable
--
-- Menu widget that shows the title of the currently focused window and that,
-- when clicked, displays the list of all currently open windows allowing to
-- switch to any of them.
-----------------------------------------------------------------------------

module System.Taffybar.Windows (
  -- * Usage
  -- $usage
    windowsNew
  , WindowsConfig(..)
  , defaultWindowsConfig
  , truncatedGetActiveLabel
  , truncatedGetMenuLabel
) where

import           Control.Monad.Reader
import qualified Graphics.UI.Gtk as Gtk
import qualified Graphics.UI.Gtk.Abstract.Widget as W
import           System.Taffybar.Information.EWMHDesktopInfo
import           System.Taffybar.Context
import           System.Taffybar.Util

-- $usage
--
-- The window switcher widget requires that the EwmhDesktops hook from the
-- XMonadContrib project be installed in your @xmonad.hs@ file:
--
-- > import XMonad.Hooks.EwmhDesktops (ewmh)
-- > main = do
-- >   xmonad $ ewmh $ defaultConfig
-- > ...

data WindowsConfig = WindowsConfig
  { getMenuLabel :: X11Window -> TaffyIO String
  -- ^ A monadic function that will be used to make a label for the window in
  -- the window menu.
  , getActiveLabel :: TaffyIO String
  -- ^ Action to build the label text for the active window.
  }

truncatedGetMenuLabel :: Int -> X11Window -> TaffyIO String
truncatedGetMenuLabel maxLength =
  fmap (Gtk.escapeMarkup . truncateString maxLength) .
  runX11Def "(nameless window)" . getWindowTitle

truncatedGetActiveLabel :: Int -> TaffyIO String
truncatedGetActiveLabel maxLength =
  truncateString maxLength <$> runX11Def "(nameless window)" getActiveWindowTitle

defaultWindowsConfig :: WindowsConfig
defaultWindowsConfig =
  WindowsConfig
  { getMenuLabel = truncatedGetMenuLabel 35
  , getActiveLabel = truncatedGetActiveLabel 35
  }

-- | Create a new Windows widget that will use the given Pager as
-- its source of events.
windowsNew :: WindowsConfig -> TaffyIO Gtk.Widget
windowsNew config = do
  label <- lift $ do
    label <- Gtk.labelNew (Nothing :: Maybe String)
    Gtk.widgetSetName label "label"
    return label

  let setLabelTitle title = lift $ Gtk.postGUIAsync $ Gtk.labelSetMarkup label title
      activeWindowUpdatedCallback _ = getActiveLabel config >>= setLabelTitle

  subscription <- subscribeToEvents ["_NET_ACTIVE_WINDOW"] activeWindowUpdatedCallback
  widget <- assembleWidget config label
  _ <- liftReader (Gtk.on widget W.unrealize) (unsubscribe subscription)
  return widget

assembleWidget :: WindowsConfig -> Gtk.Label -> TaffyIO Gtk.Widget
assembleWidget config label = ask >>= \context -> lift $ do
  ebox <- Gtk.eventBoxNew
  Gtk.widgetSetName ebox "WindowTitle"
  Gtk.containerAdd ebox label

  title <- Gtk.menuItemNew
  Gtk.widgetSetName title "title"
  Gtk.containerAdd title ebox

  switcher <- Gtk.menuBarNew
  Gtk.widgetSetName switcher "Windows"
  Gtk.containerAdd switcher title

  menu <- Gtk.menuNew
  Gtk.widgetSetName menu "menu"

  menuTop <- Gtk.widgetGetToplevel menu
  Gtk.widgetSetName menuTop "Taffybar_Windows"

  Gtk.menuItemSetSubmenu title menu

  -- These callbacks are run in the GUI thread automatically and do
  -- not need to use postGUIAsync
  _ <- Gtk.on title Gtk.menuItemActivate $ runReaderT (fillMenu config menu) context
  _ <- Gtk.on title Gtk.menuItemDeselect $ emptyMenu menu

  Gtk.widgetShowAll switcher
  return $ Gtk.toWidget switcher

-- | Populate the given menu widget with the list of all currently open windows.
fillMenu :: Gtk.MenuClass menu => WindowsConfig -> menu -> TaffyIO ()
fillMenu config menu = ask >>= \context ->
  runX11Def () $ do
    windowIds <- getWindows
    forM_ windowIds $ \windowId ->
      lift $ do
        labelText <- runReaderT (getMenuLabel config windowId) context
        let focusCallback = runReaderT (runX11 $ focusWindow windowId) context >> return True
        item <- Gtk.menuItemNewWithLabel labelText
        _ <- Gtk.on item Gtk.buttonPressEvent $ liftIO focusCallback
        Gtk.menuShellAppend menu item
        Gtk.widgetShow item

-- | Remove all contents from the given menu widget.
emptyMenu :: Gtk.MenuClass menu => menu -> IO ()
emptyMenu menu = Gtk.containerForeach menu $ \item ->
                 Gtk.containerRemove menu item >> Gtk.widgetDestroy item
