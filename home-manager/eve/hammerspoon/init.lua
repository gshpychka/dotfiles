local SUPER = { "cmd" }
local CTRL = { "ctrl" }
local SHIFT = { "shift" }
local ALT = { "alt" }
local ALT_SHIFT = { "alt", "shift" }
local CTRL_SHIFT = { "ctrl", "shift" }
local SUPER_ALT = { "cmd", "alt" }
local SUPER_SHIFT = { "cmd", "shift" }
local SUPER_CTRL = { "cmd", "ctrl" }

--
-- Window movement
--
-- These movements are inspired from i3. Make the windows 'tiling' by placing
-- them at the edge of the screens.
-- Directions are h, j, k, l similar to Vim movements.
--

-- Push the window to the left.
hs.hotkey.bind(ALT_SHIFT, "h", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    f.x = max.x
    f.y = max.y
    f.w = max.w / 2
    f.h = max.h
    win:setFrame(f)
end)

-- Push the window to the right.
hs.hotkey.bind(ALT_SHIFT, "l", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    f.x = max.x + (max.w / 2)
    f.y = max.y
    f.w = max.w / 2
    f.h = max.h
    win:setFrame(f)
end)

-- Tile the window downward, shortening its height by half.
hs.hotkey.bind(ALT_SHIFT, "k", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    f.y = max.y
    f.h = max.h / 2
    win:setFrame(f)
end)

-- Tile the window upward, shortening its height by half.
hs.hotkey.bind(ALT_SHIFT, "j", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    f.y = max.y + (max.h / 2)
    f.h = max.h / 2
    win:setFrame(f)
end)

-- Center the window without affecting its dimension.
hs.hotkey.bind(ALT_SHIFT, "c", function()
    local win = hs.window.focusedWindow()
    local screen = win:screen()

    win:centerOnScreen(screen)
end)

-- Move the window position to the left n pixels
local window_movement_pixels = 55
hs.hotkey.bind(SUPER_ALT, "h", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    f.x = f.x - window_movement_pixels
    win:setFrame(f)
end)

-- Move the window position to the right n pixels
hs.hotkey.bind(SUPER_ALT, "l", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    f.x = f.x + window_movement_pixels
    win:setFrame(f)
end)

-- Move the window position to the top n pixels
hs.hotkey.bind(SUPER_ALT, "j", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    f.y = f.y - window_movement_pixels
    win:setFrame(f)
end)

-- Move the window position to the bottom n pixels
hs.hotkey.bind(SUPER_ALT, "k", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    f.y = f.y + window_movement_pixels
    win:setFrame(f)
end)

--
-- Window switch
--
-- Directions are similar to vim.
--

hs.hotkey.bind(ALT, "h", function()
      local win = hs.window.focusedWindow()
      local screen = win:screen()

      win:focusWindowWest()
end)

hs.hotkey.bind(ALT, "l", function()
      local win = hs.window.focusedWindow()
      local screen = win:screen()

      win:focusWindowEast()
end)

hs.hotkey.bind(ALT, "j", function()
      local win = hs.window.focusedWindow()
      local screen = win:screen()

      win:focusWindowSouth()
end)

hs.hotkey.bind(ALT, "k", function()
      local win = hs.window.focusedWindow()
      local screen = win:screen()

      win:focusWindowNorth()
end)

--
-- Resize windows
--

-- Maximize the size of the window without going fullscreen.
hs.hotkey.bind(SUPER_SHIFT, "return", function()
    local win = hs.window.focusedWindow()
    local screen = win:screen()

    win:maximize()
end)

-- Minimize the window to the dock.
hs.hotkey.bind(SUPER_SHIFT, "m", function()
    local win = hs.window.focusedWindow()
    local screen = win:screen()

    win:minimize()
end)

-- Maximize the size of the window by making it go fullscreen.
hs.hotkey.bind(SUPER_SHIFT, "f", function()
    local win = hs.window.focusedWindow()
    local screen = win:screen()

    win:toggleFullScreen()
end)

-- Increase the width and height of the window.
local function resize(wPercent, hPercent)
    return function()
        local win = hs.window.focusedWindow()
        local f = win:frame()
        local screen = win:screen()
        local max = screen:frame()

        wInc = wPercent * f.w
        hInc = hPercent * f.h

        f.w = f.w + wInc
        f.x = f.x - wInc / 2

        if f.x < max.x then
            f.x = max.x
        end

        f.h = f.h + hInc
        f.y = f.y - hInc / 2
        if f.y < max.y then
            f.y = max.y
        end

        win:setFrame(f)
    end
end

local window_resize_ratio = 0.15

-- Increase/Decrease the width.
hs.hotkey.bind(SUPER_SHIFT, '.', resize(window_resize_ratio, 0))
hs.hotkey.bind(SUPER_SHIFT, ',', resize(-window_resize_ratio, 0))

-- Increase/Decrease the height.
hs.hotkey.bind(SUPER_SHIFT, '=', resize(0, window_resize_ratio))
hs.hotkey.bind(SUPER_SHIFT, '-', resize(0, -window_resize_ratio))

-- Increase/Decrease both width and height.
hs.hotkey.bind(SUPER_SHIFT, ']', resize(window_resize_ratio, window_resize_ratio))
hs.hotkey.bind(SUPER_SHIFT, '[', resize(-window_resize_ratio, -window_resize_ratio))


--
-- Screens
--

-- Move window to the left monitor.
hs.hotkey.bind(SUPER_CTRL, "h", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    win:moveOneScreenWest()
end)

-- Move window to the right monitor.
hs.hotkey.bind(SUPER_CTRL, "l", function()
    local win = hs.window.focusedWindow()
    local f = win:frame()

    win:moveOneScreenEast()
end)

--
-- Applications
--

-- Equivalent to clicking the red close button.
hs.hotkey.bind(SUPER_SHIFT, "x", function()
    local win = hs.window.focusedWindow()
    win:close()
end)


-- kill gracefully.
hs.hotkey.bind(SUPER_SHIFT, "q", function()
    local win = hs.window.focusedWindow()
    win:application():kill()
end)


--
-- Lock
--

hs.hotkey.bind(SUPER_ALT, "l", function()
    hs.caffeinate.lockScreen()
end)


--
-- Menubar
--

-- Clipboard management.
-- ref: https://www.hammerspoon.org/Spoons/ClipboardTool.html
-- function setjClipboardTool()
--     tool = hs.loadSpoon("ClipboardTool")
--     tool.show_copied_alert = false
--     tool.paste_on_select = true
--     tool:start()
--     tool:bindHotkeys({
--         toggle_clipboard = { SUPER_ALT, "p" }
--     })
-- end

-- setjClipboardTool()



--
-- Provide URL event to interact with Hammerspoon.
--
-- Ref: https://www.hammerspoon.org/docs/hs.urlevent.html
--

-- call iTerm with command
-- ref: https://iterm2.com/documentation-scripting.html
hs.urlevent.bind("terminal", function(eventName, params)
    local command = params['command']
    local dir = params['dir']

    if dir then
        cd_command = string.format([[
  tell current session of tab -1 of current window
    write text "cd %s"
  end tell
]], dir)
    else
        cd_command = ""
    end

    if command then
        exec_command = string.format([[
  tell current session of tab -1 of current window
    write text "%s"
  end tell
]], command)
    else
        exec_command = ""
    end

    hs.osascript.applescript(string.format([[
activate application "iTerm"
tell application "iTerm" to run

tell application "iTerm"
  tell current window
    create tab with default profile
  end tell

  %s

  %s
end tell
]], cd_command, exec_command))
end)


--
-- Utilities
--
-- Simple helper utilities to increse the productivity.
--


--
-- Reload
--

-- hot reload Hammerspoon itself.
hs.hotkey.bind(SUPER_ALT, "r", function()
    hs.reload()
end)