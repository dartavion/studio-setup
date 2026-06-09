-- Example workspace: three-pane layout for a typical project.
-- Copy this file, rename it (e.g. my-project.lua), and adjust WORKSPACE and ROOT.
-- Then wire it in wezterm.lua:
--
--   local my_project = require 'workspaces.my_project'
--   -- in config.keys:
--   { key = '1', mods = 'CMD', action = my_project.switch_action() },
--   -- in gui-startup:
--   my_project.create()

local wezterm = require 'wezterm'
local utils   = require 'utils'
local act     = wezterm.action
local mux     = wezterm.mux

local M = {}

local WORKSPACE = 'my-project'
local ROOT      = utils.dev .. '/my-project'   -- expands to ~/Developer/my-project

function M.switch_action()
  return act.SwitchToWorkspace {
    name  = WORKSPACE,
    spawn = { cwd = ROOT },
  }
end

function M.create()
  if utils.workspace_exists(WORKSPACE) then return end

  -- left pane: editor (nvim)
  local _, editor_pane, window = mux.spawn_window {
    workspace = WORKSPACE,
    cwd       = ROOT,
    args      = utils.login_cmd('nvim .'),
  }

  -- right pane: shell for running tests, git, etc.
  utils.add_code_pane(editor_pane, ROOT)

  window:gui_window():set_title(WORKSPACE)
  editor_pane:focus()
end

return M
