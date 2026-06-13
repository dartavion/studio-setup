local wezterm = require 'wezterm'
local M = {}

M.home = wezterm.home_dir
M.dev  = wezterm.home_dir .. '/Developer'

function M.login_cmd(cmd)
  return { 'zsh', '--login', '-c', cmd .. ' ; exec zsh' }
end

function M.shell_in(path)
  return { 'zsh', '--login', '-c', 'cd "$1" && clear; exec zsh', '--', path }
end

-- Spawns a right-side shell pane from an existing left agent pane (45% width)
function M.add_code_pane(pane, path)
  pane:split {
    direction = 'Right',
    size = 0.45,
    args = M.shell_in(path),
  }
end

-- Returns true if a workspace with the given name already exists
function M.workspace_exists(name)
  local mux = wezterm.mux
  for _, ws in ipairs(mux.get_workspace_names()) do
    if ws == name then return true end
  end
  return false
end

return M
