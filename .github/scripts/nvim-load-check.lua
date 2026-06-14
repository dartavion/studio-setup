-- Headless nvim health check, shared by the Linux and Windows CI jobs.
-- Run as:  nvim --headless <one file per filetype> -c "luafile <this>"
--
-- Catches the two failure classes that bit this repo:
--   1. plugin config-validation errors at startup (e.g. blink.cmp "Unexpected
--      field") — surface on stderr during init, asserted via the regex grep in CI
--   2. treesitter highlighter/parse breakage on a new Neovim (e.g. the 0.12
--      "attempt to call method 'range' (a nil value)") — forced here by parsing
--      every open buffer; a failure flips the exit code via :cquit.
--
-- Prints LOAD_OK and exits 0 on success; prints LOAD_ERR lines and exits 1
-- otherwise. CI also greps stderr so startup errors that don't abort init still fail.

local errors = {}

if not pcall(require, 'blink.cmp') then
  table.insert(errors, 'blink.cmp failed to load')
end

for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) then
    vim.api.nvim_set_current_buf(b)
    vim.cmd('silent! doautocmd FileType')                 -- fires the config's treesitter FileType autocmd
    local ok, parser = pcall(vim.treesitter.get_parser, b, nil, { error = false })
    if ok and parser then
      local parsed = pcall(function() parser:parse(true) end)
      if not parsed then
        table.insert(errors, ('treesitter parse failed for %s'):format(vim.bo[b].filetype))
      end
    end
  end
end

if #errors > 0 then
  for _, e in ipairs(errors) do io.stderr:write('LOAD_ERR: ' .. e .. '\n') end
  vim.cmd('cquit 1')
else
  io.stderr:write('LOAD_OK\n')
  vim.cmd('qall!')
end
