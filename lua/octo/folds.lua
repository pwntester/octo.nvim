local config = require "octo.config"

local M = {}

function M.setup() end

function M.create(bufnr, start_line, end_line, is_opened)
  if config.values.ui.use_foldtext then
    start_line = start_line - 1
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd [[setlocal foldmethod=manual]]
    vim.cmd(string.format("%d,%dfold", start_line, end_line))
    if is_opened then
      vim.cmd(string.format("%d,%dfoldopen", start_line, end_line))
    end
  end)
end

--- Folds will already have correct highlighting, but the fold background will
--- extend over the entire line. This function will make sure the whitespace
--- before the fold icon is using no background.
function M.foldtext()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.v.foldstart
  local extmark =
    vim.api.nvim_buf_get_extmarks(buf, -1, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true, type = "virt_text" })[1]

  local text = vim.tbl_get(extmark, 4, "virt_text", 1, 1)
  if text then
    return { { text:match "^%s+", "Normal" } }
  end
end

return M
