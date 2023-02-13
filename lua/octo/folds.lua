local M = {}

function M.setup() end

function M.create(bufnr, start_line, end_line, is_opened)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd [[setlocal foldmethod=manual]]
    vim.cmd(string.format("%d,%dfold", start_line, end_line))
    if is_opened then
      vim.cmd(string.format("%d,%dfoldopen", start_line, end_line))
    end
  end)
end

return M
