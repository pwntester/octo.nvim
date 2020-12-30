local format = string.format

local M = {}

function M.diff_current_quickfix_entry()
  -- cleanup windows
  for _, window in ipairs(vim.fn.getwininfo()) do
    if window.winnr ~= vim.fn.winnr() and vim.startswith(vim.fn.bufname(window.bufnr), 'fugitive:') then
      vim.cmd(format('bdelete %d', window.bufnr))
    end
  end
  vim.cmd [[cc]]
  M.add_qf_mappings()
  local qf = vim.fn.getqflist({context = 0, idx = 0})
  if qf.idx and type(qf.context) == "table" and type(qf.context.items) == "table" then
    local diff = qf.context.items[qf.idx - 1].diff or {}
    print(tostring(vim.fn.reverse(vim.fn.range(#diff))))
    for _, i in vim.fn.reverse(vim.fn.range(#diff)) do
      if i then
        vim.cmd(format("leftabove vert diffsplit %s", vim.fn.fnameescape(diff[i].filename)))
      else
        vim.cmd(format("rightbelow vert diffsplit %s", vim.fn.fnameescape(diff[i].filename)))
      end
      M.add_qf_mappings()
    end
  end
end

function M.add_qf_mappings()
  -- local mapping_opts = {script = true, silent = true, noremap = true}
  -- local bufnr = vim.api.nvim_get_current_buf()
  -- vim.api.nvim_buf_set_keymap(
  --   bufnr,
  --   "n",
  --   "]q",
  --   [[:cnext <bar> <cmd>lua require'octo.review'.diff_current_quickfix_entry()<CR>]],
  --   mapping_opts
  -- )
  -- vim.api.nvim_buf_set_keymap(
  --   bufnr,
  --   "n",
  --   "[q",
  --   [[:cprevious <bar> <cmd>lua require'octo.review'.diff_current_quickfix_entry()<CR>]],
  --   mapping_opts
  -- )

  vim.cmd [[nnoremap <buffer>]q :cnext <BAR> :lua require'octo.review'.diff_current_quickfix_entry()<CR>]]
  vim.cmd [[nnoremap <buffer>[q :cprevious <BAR> :lua require'octo.review'.diff_current_quickfix_entry()<CR>]]
  -- Reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd [[11copen]]
  vim.cmd [[wincmd p]]
end

return M
