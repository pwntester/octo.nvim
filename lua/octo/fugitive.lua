local gh = require "octo.gh"
local util = require "octo.util"
local format = string.format
local api = vim.api
local json = {
  parse = vim.fn.json_decode
}

local M = {}

function M.add_changes_qf_mappings()
  vim.cmd [[nnoremap <buffer>]q :cnext <BAR> :lua require'octo.fugitive'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[nnoremap <buffer>[q :cprevious <BAR> :lua require'octo.fugitive'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[nnoremap <buffer><C-c> :cclose <BAR> :lua require'octo.fugitive'.clean_fugitive_buffers()<CR>]]

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd [[11copen]]
  vim.cmd [[wincmd p]]
end

function M.populate_changes_qf(base, head, changes)
  -- open a new tab so we can easily clean all the windows mess
  if true then
    vim.cmd [[tabnew]]
  end

  -- run the diff between head and base commits
  vim.cmd(format("Git difftool --name-only %s..%s", base, head))

  -- update qf with gh info (additions/deletions ...)
  M.update_changes_qf(changes)

  M.diff_changes_qf_entry()
  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
  vim.cmd [[copen]]
  vim.cmd [[nnoremap <buffer> <CR> <CR><BAR>:lua require'octo.fugitive'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[wincmd p]]
end

function M.update_changes_qf(changes)
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
    if vim.startswith(api.nvim_buf_get_name(api.nvim_win_get_buf(w)), "fugitive:") then
      vim.cmd(format("bdelete %d", api.nvim_win_get_buf(w)))
    end
  end
end

function M.diff_changes_qf_entry()
  -- cleanup buffers
  M.clean_fugitive_buffers()

  -- select qf entry
  vim.cmd [[cc]]

  -- set `]q` and `[q` mappings to the qf entry buffer (head)
  M.add_changes_qf_mappings()

  -- fugitive stores changed files in qf, and what to diff against in the qf context
  local qf = vim.fn.getqflist({context = 0, idx = 0})
  if qf.idx and type(qf.context) == "table" and type(qf.context.items) == "table" then
    local item = qf.context.items[qf.idx]
    local diff = item.diff or {}
    for i = #diff - 1, 0, -1 do
      if i then
        vim.cmd(format("leftabove vert diffsplit %s", vim.fn.fnameescape(diff[i + 1].filename)))
      else
        vim.cmd(format("rightbelow vert diffsplit %s", vim.fn.fnameescape(diff[i + 1].filename)))
      end

      -- set `]q` and `[q` mappings to the diff entry buffer (base)
      M.add_changes_qf_mappings()
    end
  end
end


function M.add_comments_qf_mappings(repo, comment_bufnr, main_win)
  vim.cmd(
    format(
      "nnoremap <buffer>]q :call nvim_set_current_win(%d) <BAR> :cnext <BAR>:lua require'octo.fugitive'.show_comments_qf_entry('%s', %d, %d)<CR>",
      main_win,
      repo,
      comment_bufnr,
      main_win
    )
  )
  vim.cmd(
    format(
      "nnoremap <buffer>[q :call nvim_set_current_win(%d) <BAR> :cprevious <BAR>:lua require'octo.fugitive'.show_comments_qf_entry('%s', %d, %d)<CR>",
      main_win,
      repo,
      comment_bufnr,
      main_win
    )
  )

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd [[11copen]]
  vim.cmd [[wincmd p]]
end

function M.populate_comments_qf(repo, number, selection)
  local curl = format("/repos/%s/pulls/%d/reviews/%d/comments", repo, number, selection.review.id)
  gh.run(
    {
      args = {"api", curl},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local items = {}
          local comments = json.parse(output)
          for _, comment in ipairs(comments) do
            local item = {}
            --item.bufnr = vim.fn.bufnr(comment.path)
            item.filename = comment.path
            local _, _, line = string.find(comment.diff_hunk, "@@%s+-%d+,%d+%s%+(%d+),%d+%s@@")
            item.lnum = line + comment.position - 2
            item.text = vim.split(comment.body, "\n")[1]
            item.pattern = comment.id

            -- print(format("Gedit %s:%s", comment.commit_id, comment.path))
            -- print(format("fugitive://%s/.git//%s/%s", vim.fn.getcwd(), comment.commit_id, comment.path))

            table.insert(items, item)
          end

          -- populate qf
          vim.fn.setqflist(items)

          -- create comment buffer
          local comment_bufnr = api.nvim_create_buf(false, true)

          -- new tab to hold the main, qf and comment windows
          if true then
            vim.cmd [[tabnew]]
          end
          local main_win = api.nvim_get_current_win()

          -- open qf
          vim.cmd [[copen]]

          -- add a <CR> mapping to the qf window
          vim.cmd(
            format(
              "nnoremap <buffer> <CR> <CR><BAR>:lua require'octo.fugitive'.show_comments_qf_entry('%s', %d, %d)<CR>",
              repo,
              comment_bufnr,
              main_win
            )
          )

          -- add ]q and [q mappints to the qf window
          M.add_comments_qf_mappings(repo, comment_bufnr, main_win)

          -- get comment for first element in qf
          M.show_comments_qf_entry(repo, comment_bufnr, main_win)

          -- back to qf
          vim.cmd [[wincmd p]]

          -- create comment window and set the comment buffer
          vim.cmd [[set splitright]]
          vim.cmd [[vsplit]]
          api.nvim_set_current_buf(comment_bufnr)

          -- set mappings to the comment window
          M.add_comments_qf_mappings(repo, comment_bufnr, main_win)
        end
      end
    }
  )
end

function M.show_comments_qf_entry(repo, comment_bufnr, main_win)
  -- select qf entry
  vim.cmd [[cc]]

  -- set [q and ]q mappings for the main window
  M.add_comments_qf_mappings(repo, comment_bufnr, main_win)

  -- get comment details
  local qf = vim.fn.getqflist({idx = 0, items = 0})
  local idx = qf.idx or 0
  local items = qf.items or {}
  local selected_item = items[idx]
  local comment_id = selected_item.pattern
  local comment_url = format("/repos/%s/pulls/comments/%d", repo, comment_id)

  -- jump to comment line in main window
  local row = (selected_item.lnum) or 1
  api.nvim_win_set_cursor(main_win, {row, 1})

  -- fetch comment details and show them in the comment buffer
  gh.run(
    {
      args = {"api", comment_url},
      cb = function(output)
        local comment = json.parse(output)
        api.nvim_buf_set_lines(comment_bufnr, 0, -1, false, vim.split(comment.diff_hunk, "\n"))
        api.nvim_buf_set_lines(comment_bufnr, -1, -1, false, {""})
        api.nvim_buf_set_lines(comment_bufnr, -1, -1, false, vim.split(comment.body, "\n"))
        api.nvim_buf_set_option(comment_bufnr, "filetype", "diff")
      end
    }
  )
end

return M
