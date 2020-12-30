local format = string.format
local api = vim.api

local M = {}

function M.diff_pr(base, head, changes)
  vim.cmd(format("Git difftool --name-only %s..%s", base, head))

  -- update qf with gh info (additions/deletions ...)
  M.update_qf(changes)

  M.diff_current_quickfix_entry()
  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
  vim.cmd [[copen]]
  vim.cmd [[nnoremap <buffer> <CR> <CR><BAR>:lua require'octo.fugitive'.diff_current_quickfix_entry()<CR>]]
  vim.cmd [[wincmd p]]
end

function M.update_qf(changes)
  print("foo")
  local qf = vim.fn.getqflist({context = 0, items = 0})
  local items = qf.items
  for _, item in ipairs(items) do
    for _, change in ipairs(changes) do
      print(item.module, change.branch, change.filename)
      if item.module == format("%s:%s", change.branch, change.filename) then
        item.text = change.text .. " " .. change.status
      end
    end
  end
  vim.fn.setqflist({}, "r", {context = qf.context, items = items})
end

function M.clean_fugitive_buffers()
  for _, w in ipairs(api.nvim_list_wins()) do
    --if w ~= api.nvim_get_current_win() and vim.startswith(api.nvim_buf_get_name(api.nvim_win_get_buf(w)), "fugitive:") then
    if vim.startswith(api.nvim_buf_get_name(api.nvim_win_get_buf(w)), "fugitive:") then
      vim.cmd(format('bdelete %d', api.nvim_win_get_buf(w)))
    end
  end
end

function M.diff_current_quickfix_entry()
  -- cleanup buffers
  M.clean_fugitive_buffers()

  -- jump to qf entry
  vim.cmd [[cc]]

  -- set `]q` and `[q` mappings to the qf entry buffer (head)
  M.add_qf_mappings()

  -- fugitive stores changed files in qf, and what to diff against in the qf context
  local qf = vim.fn.getqflist({context = 0, idx = 0})
  if qf.idx and type(qf.context) == "table" and type(qf.context.items) == "table" then
    local item = qf.context.items[qf.idx]
    local diff = item.diff or {}
    for i=#diff-1, 0, -1 do
      if i then
        vim.cmd(format("leftabove vert diffsplit %s", vim.fn.fnameescape(diff[i+1].filename)))
      else
        vim.cmd(format("rightbelow vert diffsplit %s", vim.fn.fnameescape(diff[i+1].filename)))
      end

      -- set `]q` and `[q` mappings to the diff entry buffer (base)
      M.add_qf_mappings()
    end
  end
end

function M.add_qf_mappings()
  vim.cmd [[nnoremap <buffer>]q :cnext <BAR> :lua require'octo.fugitive'.diff_current_quickfix_entry()<CR>]]
  vim.cmd [[nnoremap <buffer>[q :cprevious <BAR> :lua require'octo.fugitive'.diff_current_quickfix_entry()<CR>]]
  vim.cmd [[nnoremap <buffer><C-c> :cclose <BAR> :lua require'octo.fugitive'.clean_fugitive_buffers()<CR>]]

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd [[11copen]]
  vim.cmd [[wincmd p]]
end

return M
