local wezterm = require 'wezterm'
local mux     = wezterm.mux
local act     = wezterm.action
local config  = wezterm.config_builder()

-- ── Shell & PATH ─────────────────────────────────────────────────────────────

config.default_prog = { '/bin/zsh', '--login' }

local home = wezterm.home_dir
config.set_environment_variables = {
  PATH = '/opt/homebrew/bin:'
      .. '/opt/homebrew/sbin:'
      .. '/usr/local/bin:'
      .. home .. '/.local/bin:'
      .. '/usr/bin:/bin:/usr/sbin:/sbin',
}

-- ── Appearance ───────────────────────────────────────────────────────────────

config.color_scheme                 = 'Tokyo Night'
config.font                         = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Regular' })
config.font_size                    = 13.0
config.window_padding               = { left = 8, right = 8, top = 8, bottom = 8 }
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom            = true
config.use_fancy_tab_bar            = false
config.window_decorations           = 'RESIZE'

-- ── Keybindings ──────────────────────────────────────────────────────────────

config.keys = {
  -- Pane splits
  { key = 'd', mods = 'CMD',       action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'CMD|SHIFT', action = act.SplitVertical   { domain = 'CurrentPaneDomain' } },
  -- Pane navigation (vim-style)
  { key = 'h', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection 'Left'  },
  { key = 'l', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection 'Up'    },
  { key = 'j', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection 'Down'  },
  { key = 'z', mods = 'CMD|SHIFT', action = act.TogglePaneZoomState            },
  -- Tab management
  { key = 'w', mods = 'CMD',       action = act.CloseCurrentPane { confirm = false } },
  { key = 't', mods = 'CMD',       action = act.SpawnTab 'CurrentPaneDomain'         },
  { key = '[', mods = 'CMD|SHIFT', action = act.ActivateTabRelative(-1)              },
  { key = ']', mods = 'CMD|SHIFT', action = act.ActivateTabRelative(1)               },
  -- Workspace picker
  { key = 'o', mods = 'CMD',       action = act.ShowLauncherArgs { flags = 'WORKSPACES' } },
  -- Per-project workspace shortcuts go here, e.g.:
  -- { key = '1', mods = 'CMD', action = require('workspaces.my_project').switch_action() },
}

-- ── Status bar — workspace name ───────────────────────────────────────────────

wezterm.on('update-right-status', function(window)
  local workspace = window:active_workspace()
  window:set_right_status(wezterm.format {
    { Foreground = { AnsiColor = 'Silver' } },
    { Text = '  ' .. workspace .. '  ' },
  })
end)

-- ── Tab titles — current directory ───────────────────────────────────────────

wezterm.on('format-tab-title', function(tab)
  local pane  = tab.active_pane
  local cwd   = pane.current_working_dir
  if cwd then
    local path  = cwd.file_path
    local short = path:match('([^/]+)$') or path
    return ' ' .. short .. ' '
  end
  return ' ' .. tab.active_pane.title .. ' '
end)

-- ── Startup ───────────────────────────────────────────────────────────────────
-- Load project workspaces and auto-spawn on startup.
-- Add requires here as you create workspace files, e.g.:
--   local my_project = require 'workspaces.my_project'
--   my_project.create()

wezterm.on('gui-startup', function()
  mux.spawn_window {}
end)

return config
