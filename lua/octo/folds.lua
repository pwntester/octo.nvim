function _G.OctoFoldText()
  return "..."
end

local M = {}

function M.create(start_line, end_line, is_opened)
  vim.cmd(string.format("%d,%dfold", start_line, end_line))
  if is_opened then
    vim.cmd(string.format("%d,%dfoldopen", start_line, end_line))
  end
end

return M
