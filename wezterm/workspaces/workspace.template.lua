-- Copy this file to workspaces/<your-project>.lua and fill in the blanks.
-- Then require it in wezterm.lua and call .create() in gui-startup.

local wezterm = require 'wezterm'
local mux     = wezterm.mux
local act     = wezterm.action
local u       = require 'utils'

local M = {}
local NAME = 'my-project'           -- workspace name shown in the switcher

function M.create()
  local root = u.dev .. '/my-project'

  -- Main tab: agent pane left, shell pane right
  local tab, pane, window = mux.spawn_window {
    workspace = NAME,
    cwd  = root,
    args = u.login_cmd('claude'),   -- swap for 'zsh' if you don't want claude here
  }
  tab:set_title('my-project')
  u.add_code_pane(pane, root)

  -- Extra shell tab
  local shell_tab, _ = window:spawn_tab {
    cwd  = root,
    args = { 'zsh', '--login' },
  }
  shell_tab:set_title('shell')

  tab:activate()
  return window
end

-- Bind this to a key in wezterm.lua:
--   { key = '1', mods = 'CMD', action = require('workspaces.my_project').switch_action() }
function M.switch_action()
  return wezterm.action_callback(function(window, pane)
    if not u.workspace_exists(NAME) then M.create() end
    window:perform_action(act.SwitchToWorkspace { name = NAME }, pane)
  end)
end

return M
