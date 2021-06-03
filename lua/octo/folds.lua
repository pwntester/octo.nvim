local M = {}

function _G.octo_foldtext()
  --print(vim.line(vim.v.foldstart - 1))
  --print(vim.v.foldstart, vim.api.nvim_get_current_buf())
  --print(vim.v.foldstart, util.get_comment_at_line(vim.v.foldstart))
  return "  ..."
end

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
