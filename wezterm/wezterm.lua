local wezterm    = require 'wezterm' ---@type Wezterm
local mux        = wezterm.mux
local act        = wezterm.action
local config     = wezterm.config_builder() ---@type Config

local home       = wezterm.home_dir
local target     = wezterm.target_triple -- e.g. "x86_64-pc-windows-msvc"
local is_windows = target:find('windows') ~= nil

-- ── Plugins ──────────────────────────────────────────────────────────────────
-- Loaded from GitHub via wezterm.plugin.require (cloned once into the plugin
-- cache; never auto-updates). Vetted commit SHAs are recorded in
-- wezterm/plugins.lock; run wezterm/check-plugins.sh (or .ps1 on Windows) to detect drift (e.g. after
-- wezterm.plugin.update_all()). require() can't pin to a ref, so this is
-- drift/tamper detection, not true pinning — review upstream before updating.
local tabline    = wezterm.plugin.require 'https://github.com/michaelbrusegard/tabline.wez'
local resurrect  = wezterm.plugin.require 'https://github.com/MLFlexer/resurrect.wezterm'
local smart_ssh  = wezterm.plugin.require 'https://github.com/DavidRR-F/smart_ssh.wezterm'

-- ── Shell & PATH ─────────────────────────────────────────────────────────────
-- macOS/Linux only — on Windows, WezTerm uses the default shell (PowerShell or
-- a WSL distro) and inherits PATH from the system environment.

if not is_windows then
  config.default_prog = { '/bin/zsh', '--login' }
  config.set_environment_variables = {
    PATH = '/opt/homebrew/bin:'
        .. '/opt/homebrew/sbin:'
        .. '/usr/local/bin:'
        .. home .. '/.local/bin:'
        .. '/usr/bin:/bin:/usr/sbin:/sbin',
  }
end

-- ── Appearance ───────────────────────────────────────────────────────────────

config.color_scheme                               = 'Ocean Dark (Gogh)'
config.font                                       = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Regular' })
config.font_size                                  = 16.0
config.window_padding                             = { left = 8, right = 8, top = 8, bottom = 8 }
config.hide_tab_bar_if_only_one_tab               = false
config.tab_bar_at_bottom                          = true
config.use_fancy_tab_bar                          = false
config.window_decorations                         = 'RESIZE'

-- Quality-of-life
config.inactive_pane_hsb                          = { saturation = 0.8, brightness = 0.6 } -- dim unfocused panes
config.scrollback_lines                           = 10000                                  -- default is a stingy 3500
config.front_end                                  = 'WebGpu'                               -- smoother GPU rendering
config.macos_window_background_blur               = 20                                     -- macOS only; ignored elsewhere
config.audible_bell                               = 'Disabled'
config.adjust_window_size_when_changing_font_size = false
config.window_background_opacity                  = 0.8

-- ── Keybindings ──────────────────────────────────────────────────────────────
-- Leader (tmux-style prefix). Press CMD+a, then the next key.
config.leader                                     = { key = 'a', mods = 'CMD', timeout_milliseconds = 1000 }

config.keys                                       = {
  -- Pane splits
  { key = 'd', mods = 'CMD',          action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'CMD|SHIFT',    action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  -- Pane navigation (vim-style)
  { key = 'h', mods = 'CMD|SHIFT',    action = act.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CMD|SHIFT',    action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CMD|SHIFT',    action = act.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CMD|SHIFT',    action = act.ActivatePaneDirection 'Down' },
  { key = 'z', mods = 'CMD|SHIFT',    action = act.TogglePaneZoomState },
  -- Tab management
  { key = 'w', mods = 'CMD',          action = act.CloseCurrentPane { confirm = false } },
  { key = 't', mods = 'CMD',          action = act.SpawnTab 'CurrentPaneDomain' },
  { key = '[', mods = 'CMD|SHIFT',    action = act.ActivateTabRelative(-1) },
  { key = ']', mods = 'CMD|SHIFT',    action = act.ActivateTabRelative(1) },
  -- Workspace picker (built-in)
  { key = 'o', mods = 'CMD',          action = act.ShowLauncherArgs { flags = 'WORKSPACES' } },

  -- Plugin actions (leader-prefixed so they never shadow shell control keys)
  -- Workspace switching uses the built-in launcher (CMD+o, defined above).
  -- smart_ssh: pick a host from ~/.ssh/config
  { key = 's', mods = 'LEADER|SHIFT', action = smart_ssh.tab() },    -- new tab
  { key = '5', mods = 'LEADER',       action = smart_ssh.hsplit() }, -- horizontal split
  { key = "'", mods = 'LEADER',       action = smart_ssh.vsplit() }, -- vertical split
  -- resurrect: LEADER+w saves current workspace state, LEADER+r restores
  {
    key = 'w',
    mods = 'LEADER',
    action = wezterm.action_callback(function(win, pane)
      resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
      win:toast_notification('resurrect', 'workspace state saved', nil, 2000)
    end)
  },
  {
    key = 'r',
    mods = 'LEADER',
    action = wezterm.action_callback(function(win, pane)
      resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
        local kind = string.match(id, '^([^/]+)')
        id = string.match(id, '([^/]+)$')
        id = string.match(id, '(.+)%..+$')
        local opts = {
          relative        = true,
          restore_text    = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        }
        if kind == 'workspace' then
          local state = resurrect.state_manager.load_state(id, 'workspace')
          resurrect.workspace_state.restore_workspace(state, opts)
        elseif kind == 'window' then
          local state = resurrect.state_manager.load_state(id, 'window')
          resurrect.window_state.restore_window(pane:window(), state, opts)
        end
      end)
    end)
  },

  -- Per-project workspace shortcuts go here, e.g.:
  -- { key = '1', mods = 'CMD', action = require('workspaces.my_project').switch_action() },
}

-- ── Status bar — tabline.wez ─────────────────────────────────────────────────
-- tabline owns format-tab-title and update-status (replaces the manual
-- update-right-status / format-tab-title handlers).

-- WezTerm Active Agent HUD — custom contextual component that dynamically
-- detects the active process/agent running in your focused pane. Displays Claude Cost
-- when active, GitHub Copilot when active, Neovim, or standard Shell status.
local active_agent_hud                            = (function()
  local cached, last_check = '', 0
  local script = home .. '/.config/wezterm/scripts/today-cost.sh'

  local function get_focused_pane()
    if not wezterm.gui then return nil end
    for _, win in ipairs(wezterm.gui.gui_windows()) do
      if win:is_focused() then
        return win:active_pane()
      end
    end
    return nil
  end

  return function()
    local pane = get_focused_pane()
    if not pane then return '' end

    local title = (pane:get_title() or ''):lower()
    local proc = (pane:get_foreground_process_name() or ''):lower()

    if proc:find('claude') or title:find('claude') then
      local now = os.time()
      if now - last_check >= 30 then
        last_check = now
        local ok, success, stdout = pcall(wezterm.run_child_process, { '/bin/bash', script })
        if ok and success and stdout then
          cached = (stdout:gsub('%s+$', ''))
        end
      end
      local cost = cached ~= '' and cached or '$0.00'
      return (wezterm.nerdfonts.md_robot or '🤖') .. ' Claude (' .. cost .. ')'
    elseif proc:find('copilot') or title:find('copilot') or title:find('gh-copilot') then
      return (wezterm.nerdfonts.md_github or '🐙') .. ' Copilot'
    elseif proc:find('nvim') or title:find('nvim') or title:find('vim') then
      return (wezterm.nerdfonts.custom_neovim or '📝') .. ' Neovim'
    else
      return (wezterm.nerdfonts.md_terminal or '💻') .. ' Shell'
    end
  end
end)()

local tabline_y                                   = { 'datetime', 'battery' }
if not is_windows then
  table.insert(tabline_y, 1, active_agent_hud)
end

tabline.setup {
  options = {
    icons_enabled = true,
    theme         = 'Tokyo Night',
    tabs_enabled  = true,
  },
  sections = {
    tabline_a    = { 'mode' },
    tabline_b    = { 'workspace' },
    tabline_c    = { ' ' },
    tab_active   = { 'index', { 'parent', padding = 0 }, '/', { 'cwd', padding = { left = 0, right = 1 } } },
    tab_inactive = { 'index', { 'process', padding = { left = 0, right = 1 } } },
    tabline_x    = { 'ram', 'cpu' },
    tabline_y    = tabline_y,
    tabline_z    = { 'domain' },
  },
}
tabline.apply_to_config(config)
-- apply_to_config forces the bar to the top; keep the bottom preference.
config.tab_bar_at_bottom = true

-- SSH domains from ~/.ssh/config (keys defined above; must run after config.keys).
smart_ssh.apply_to_config(config)

-- resurrect: periodic background save (every 15 min). Restore with LEADER+r.
-- Intentionally NOT hooked into gui-startup (startup is owned below).
resurrect.state_manager.periodic_save()

-- ── Startup ───────────────────────────────────────────────────────────────────
-- Load project workspaces and auto-spawn on startup.
-- Add requires here as you create workspace files, e.g.:
--   local my_project = require 'workspaces.my_project'
--   my_project.create()

wezterm.on('gui-startup', function()
  mux.spawn_window {}
end)

return config
