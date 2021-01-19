local octo = require "octo"
local writers = require "octo.writers"
local signs = require "octo.signs"
local util = require "octo.util"
local constants = require "octo.constants"
local format = string.format
local vim = vim
local api = vim.api

-- TODO: save main window buffers for cleanup on <C-c>

local M = {}

M.review_comments = {}

local qf_height = vim.g.octo_qf_height or math.floor(vim.o.lines * 0.2)

function M.populate_changes_qf(changes, opts)
  -- open a new tab so we can easily clean all the windows mess
  if true then
    vim.cmd [[tabnew %]]
  end

  -- run the diff between head and base commits
  vim.cmd(format("Git difftool --name-only %s..%s", opts.baseRefName, opts.headRefName))

  local qf = vim.fn.getqflist({size = 0})
  if qf.size == 0 then
    api.nvim_err_writeln(format("No changes found for pr"))
    return
  end

  -- update qf with gh info (additions/deletions ...)
  M.update_changes_qf(changes, opts)

  M.diff_changes_qf_entry()
  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[nnoremap <silent><buffer> <CR> <CR><BAR>:lua require'octo.reviews'.diff_changes_qf_entry()<CR>]]
  vim.cmd [[wincmd p]]
end

function M.update_changes_qf(changes, opts)
  local qf = vim.fn.getqflist({context = 0, items = 0})

  -- update item's text
  local items = qf.items
  for _, item in ipairs(items) do
    for _, change in ipairs(changes) do
      if item.module == format("%s:%s", opts.baseRefName, change.filename) then
        item.pattern = change.text .. " " .. change.status
      end
    end
  end

  -- update context wiht SHA info
  qf.context.left_sha = opts.baseRefSHA
  qf.context.right_sha = opts.headRefSHA

  -- update context items with diff
  for i, ctxitem in ipairs(qf.context.items) do
    ctxitem.patch = changes[i].patch
  end

  vim.fn.setqflist({}, "r", {context = qf.context, items = items})
end

function M.clean_fugitive_buffers()
  local tabpage = api.nvim_get_current_tabpage()
  for _, w in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if api.nvim_win_is_valid(w) then
      local bufnr = api.nvim_win_get_buf(w)
      local bufname = api.nvim_buf_get_name(bufnr)
      if vim.startswith(bufname, "fugitive:") then
        vim.cmd(format("bdelete! %d", bufnr))
      end
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
  local qf = vim.fn.getqflist({context = 0, idx = 0, items = 0, winid = 0})
  if qf.idx and type(qf.context) == "table" and type(qf.context.items) == "table" then
    local ctxitem = qf.context.items[qf.idx]
    local left_sha = qf.context.left_sha
    local right_sha = qf.context.right_sha
    local diff = ctxitem.diff or {}
    for i = #diff - 1, 0, -1 do
      if i then
        vim.cmd(format("leftabove vert diffsplit %s", vim.fn.fnameescape(diff[i + 1].filename)))
      else
        vim.cmd(format("rightbelow vert diffsplit %s", vim.fn.fnameescape(diff[i + 1].filename)))
      end

      -- cursor should be located at LEFT split
      local left_bufnr = api.nvim_get_current_buf()
      local left_bufname = api.nvim_buf_get_name(left_bufnr)
      M.add_changes_qf_mappings()

      -- move to RIGHT split
      vim.cmd [[wincmd l]]
      local right_bufnr = api.nvim_get_current_buf()
      local right_bufname = api.nvim_buf_get_name(right_bufnr)
      M.add_changes_qf_mappings()

      -- move to first chunk
      vim.cmd [[normal! ]c]]

      local valid_left_ranges = {}
      local valid_right_ranges = {}
      for _, line in ipairs(vim.split(ctxitem.patch, "\n")) do
        if vim.startswith(line, "@@") then
          local found, _, left_start, left_length, right_start, right_length = string.find(line, "@@%s%-(%d+),(%d+)%s%+(%d+),(%d+)%s@@")
          if found then
            table.insert(valid_left_ranges, {tonumber(left_start), left_start + left_length - 1})
            table.insert(valid_right_ranges, {tonumber(right_start), right_start + right_length - 1})
          end
        end
      end

      -- set diff info as buf vars
      local left_props = {
        side = "LEFT",
        sha = left_sha,
        qf_idx = qf.idx,
        qf_winid = qf.winid,
        ranges = valid_left_ranges,
        bufname = left_bufname
      }
      local right_props = {
        side = "RIGHT",
        sha = right_sha,
        qf_idx = qf.idx,
        qf_winid = qf.winid,
        ranges = valid_right_ranges,
        bufname = right_bufname
      }
      api.nvim_buf_set_var(left_bufnr, "OctoDiffProps", left_props)
      api.nvim_buf_set_var(right_bufnr, "OctoDiffProps", right_props)
    end
  end
end

function M.add_review_comment(line1, line2)
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if status and props then

    -- TODO: check we are in a valid range

    -- create new buffer
    local comment_bufnr = api.nvim_create_buf(false, true)
    print(comment_bufnr)

    -- move to qf win
    api.nvim_set_current_win(props.qf_winid)

    -- create new win and show comment bufnr
    vim.cmd(format("rightbelow vert sbuffer %d", comment_bufnr))
    vim.cmd [[startinsert]]

    -- create new comment
    local comment = {
      side = props.side,
      sha = props.sha,
      qf_idx = props.idx,
      qf_winid = props.winid,
      comment_bufnr = comment_bufnr,
      line1 = line1,
      line2 = line2,
      body = ""
    }
    local bufname = format("octo_comment://%s.%d.%d", string.gsub(props.bufname, "fugitive://", ""), line1, line2)
    M.review_comments[bufname] = comment
    api.nvim_buf_set_var(comment_bufnr, "OctoDiffProps", props)
    api.nvim_buf_set_option(comment_bufnr, "filetype", "octo_reviewcomment")
    api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
    api.nvim_buf_set_name(comment_bufnr, bufname)
  end
end

function M.save_review_comment()
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if status and props then
    local bufname = api.nvim_buf_get_name(bufnr)
    local comment = M.review_comments[bufname]
    comment.body = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    M.review_comments[bufname] = comment

    -- TODO: close win and delete buffer
    --vim.cmd("bdelete! "..bufnr)
  end
end

function M.populate_reviewthreads_qf(repo, number, reviewthreads)
  local items = {}
  local qf = vim.fn.getqflist({winid = 0})
  local qf_width = vim.fn.winwidth(qf.winid) * 0.4

  local process_threads = function(threads)
    for _, thread in ipairs(threads) do
      local comment = thread.comments.nodes[1]
      local mods = ""
      if thread.isResolved then
        mods = "RESOLVED "
      end
      if thread.isOutdated then
        mods = mods .. "OUTDATED "
      end
      local comment_id = util.graph2rest(comment.id)
      local lnum = thread.line
      if not lnum or lnum == vim.NIL then
        lnum = thread.originalLine
      end
      table.insert(
        items,
        {
          filename = thread.path,
          lnum = lnum,
          text = format(
            "%s (%s) %s%s...",
            comment.author.login,
            string.lower(comment.authorAssociation),
            mods,
            string.sub(vim.split(comment.body, "\n")[1], 0, qf_width)
          ),
          pattern = format("%s/%s", thread.id, comment_id)
        }
      )
    end
  end

  local resolved_threads =
    vim.tbl_filter(
    function(item)
      return item.isResolved
    end,
    reviewthreads
  )
  local unresolved_threads =
    vim.tbl_filter(
    function(item)
      return not item.isResolved
    end,
    reviewthreads
  )

  -- add the unresolved threads first
  process_threads(unresolved_threads)

  -- add the resolved threads later
  -- TODO: add an option to not show them at all
  process_threads(resolved_threads)

  if #items == 0 then
    api.nvim_err_writeln("No comments found")
    return
  end

  -- populate qf
  vim.fn.setqflist(items)

  -- new tab to hold the main, qf and comment windows
  if true then
    vim.cmd(format("tabnew %s", items[1].filename))
  end
  local main_win = api.nvim_get_current_win()

  -- save review comments in main window var
  api.nvim_win_set_var(main_win, "reviewthreads", reviewthreads)

  -- open qf
  vim.cmd(format("%dcopen", qf_height))
  local qf_win = api.nvim_get_current_win()

  -- highlight qf entries
  vim.cmd [[call matchadd("Comment", "\(.*\)")]]
  vim.cmd [[call matchadd("OctoNvimCommentUser", "|\\s\\zs[^(]+\\ze\(")]]
  vim.cmd [[call matchadd("OctoNvimBubbleRed", "OUTDATED")]]
  vim.cmd [[call matchadd("OctoNvimBubbleGreen", "RESOLVED")]]
  vim.cmd [[call matchadd("OctoNvimBubbleDelimiter", "")]]
  vim.cmd [[call matchadd("OctoNvimBubbleDelimiter", "")]]

  -- add a <CR> mapping to the qf window
  vim.cmd(
    format(
      "nnoremap <silent><buffer> <CR> <CR><BAR>:lua require'octo.reviews'.show_reviewthread_qf_entry('%s', %d, %d)<CR>",
      repo,
      number,
      main_win
    )
  )

  -- add mappings to the qf window
  M.add_reviewthread_qf_mappings(repo, number, main_win)

  -- back to qf
  api.nvim_set_current_win(qf_win)
  api.nvim_win_set_option(qf_win, "number", false)
  api.nvim_win_set_option(qf_win, "relativenumber", false)

  -- create comment window and set the comment buffer
  local reviewthread_position = "main"
  if reviewthread_position == "main" then
    api.nvim_set_current_win(main_win)
  elseif reviewthread_position == "qf" then
    api.nvim_set_current_win(qf_win)
  end
  vim.cmd("rightbelow vsplit %")
  local comment_win = api.nvim_get_current_win()
  api.nvim_win_set_option(comment_win, "number", false)
  api.nvim_win_set_option(comment_win, "relativenumber", false)

  -- jump to main window and select qf entry
  api.nvim_set_current_win(main_win)
  api.nvim_win_set_var(main_win, "comment_win", comment_win)
  vim.cmd [[cc]]

  -- show comment for first element in qf
  M.show_reviewthread_qf_entry(repo, number, main_win)
end

function M.clean_reviewthread_buffers()
  local tabpage = api.nvim_get_current_tabpage()
  for _, w in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if api.nvim_win_is_valid(w) then
      local bufnr = api.nvim_win_get_buf(w)
      local ft = api.nvim_buf_get_option(bufnr, "filetype")
      if ft == "octo_reviewthread" then
        vim.cmd(format("bdelete %d", bufnr))
      end
    end
  end
end

function M.show_reviewthread_qf_entry(repo, number, main_win)
  -- set mappings for the main window buffer
  M.add_reviewthread_qf_mappings(repo, number, main_win)
  local main_bufnr = api.nvim_get_current_buf()

  -- get comment details
  local qf = vim.fn.getqflist({idx = 0, items = 0})
  local idx = qf.idx or 0
  local items = qf.items or {}
  local selected_item = items[idx]
  local ids = selected_item.pattern
  local reviewthread_id = vim.split(ids, "/")[1]
  local comment_id = vim.split(ids, "/")[2]

  -- jump back to main win and go to comment line
  api.nvim_set_current_win(main_win)
  local row = (selected_item.lnum) or 1
  local ok = pcall(api.nvim_win_set_cursor, main_win, {row, 1})
  if not ok then
    api.nvim_err_writeln("Cannot move cursor to line " .. row)
  end

  -- jump to comment window
  local comment_win = api.nvim_win_get_var(main_win, "comment_win")
  api.nvim_set_current_win(comment_win)

  -- get cached thread
  local reviewthreads = api.nvim_win_get_var(main_win, "reviewthreads")
  local reviewthread
  for _, thread in ipairs(reviewthreads) do
    if reviewthread_id == thread.id then
      reviewthread = thread
    end
  end

  local bufnr =
    vim.fn.bufnr(format("octo://%s/pull/%d/reviewthread/%s/comment/%s", repo, number, reviewthread_id, comment_id))
  if bufnr > -1 then
    -- show existing comment buffer
    api.nvim_win_set_buf(comment_win, bufnr)
  else
    -- create new comment buffer
    bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_var(bufnr, "repo", repo)
    api.nvim_buf_set_var(bufnr, "number", number)
    api.nvim_buf_set_option(bufnr, "filetype", "octo_reviewthread")
    api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    api.nvim_buf_set_name(
      bufnr,
      format("octo://%s/pull/%d/reviewthread/%s/comment/%s", repo, number, reviewthread_id, comment_id)
    )
    api.nvim_win_set_buf(comment_win, bufnr)

    -- add mappings to the comment window buffer
    M.add_reviewthread_qf_mappings(repo, number, main_win)
    octo.apply_buffer_mappings(bufnr, "reviewthread")

    -- write path
    writers.write_title(bufnr, reviewthread.path, 1)

    -- write diff hunk
    local main_comment = reviewthread.comments.nodes[1]
    writers.write_diff_hunk(bufnr, main_comment.diffHunk, 3)

    -- write thread
    api.nvim_buf_set_var(bufnr, "comments", {})
    for _, comment in ipairs(reviewthread.comments.nodes) do
      writers.write_comment(bufnr, comment)
    end
  end

  -- highlight commented lines
  M.highlight_lines(main_bufnr, reviewthread.startLine, reviewthread.line)

  -- show signs
  signs.render_signcolumn(bufnr)

  -- autocmds
  vim.cmd [[ augroup octo_reviewthread_autocmds ]]
  vim.cmd [[ au! * <buffer> ]]
  vim.cmd [[ au TextChanged <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ au TextChangedI <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ augroup END ]]
end

function M.highlight_lines(bufnr, startLine, endLine)
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_HIGHLIGHT_NS, 0, -1)
  signs.unplace(bufnr)
  if not endLine then
    return
  end
  startLine = startLine or endLine
  for line = startLine, endLine do
    api.nvim_buf_add_highlight(bufnr, constants.OCTO_HIGHLIGHT_NS, "OctoNvimCommentLine", line - 1, 0, -1)
    signs.place("comment", bufnr, line - 1)
  end
end

-- MAPPINGS
function M.add_reviewthread_qf_mappings(repo, number, main_win)
  -- vim.cmd(
  --   format(
  --     "nnoremap <silent><buffer>]c :lua require'octo.reviews'.next_file_comment('%s', %d, %d)<CR>",
  --     repo,
  --     number,
  --     main_win
  --   )
  -- )
  -- vim.cmd(
  --   format(
  --     "nnoremap <silent><buffer>[c :lua require'octo.reviews'.prev_file_comment('%s', %d, %d)<CR>",
  --     repo,
  --     number,
  --     main_win
  --   )
  -- )
  vim.cmd(
    format(
      "nnoremap <silent><buffer>]q :lua require'octo.reviews'.next_comment('%s', %d, %d)<CR>",
      repo,
      number,
      main_win
    )
  )
  vim.cmd(
    format(
      "nnoremap <silent><buffer>[q :lua require'octo.reviews'.prev_comment('%s', %d, %d)<CR>",
      repo,
      number,
      main_win
    )
  )

  vim.cmd [[nnoremap <silent><buffer><C-c> :tabclose <BAR> :lua require'octo.reviews'.clean_reviewthread_buffers()<CR>]]

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[wincmd p]]
end

-- function M.get_file_comment_lines(repo, number, main_win)
--   local reviewthreads = api.nvim_win_get_var(main_win, "reviewthreads")
--   local bufnr = api.nvim_win_get_buf(main_win)
--   local pr_bufnr = vim.fn.bufnr(format("octo://%s/pull/%d", repo, number))
--   local comments = api.nvim_buf_get_var(pr_bufnr, "pr_comments")
--   local lines = {}
--   for _, c in ipairs(reviewthreads) do
--     local comment = comments[tostring(c.id)]
--     if comment and comment.path == vim.fn.bufname(bufnr) then
--       table.insert(lines, comment.original_line)
--     end
--   end
--   table.sort(
--     lines,
--     function(a, b)
--       return a < b
--     end
--   )
--   return lines
-- end
--
-- function M.next_file_comment(repo, number, main_win)
--   api.nvim_set_current_win(main_win)
--   local lines = M.get_file_comment_lines(repo, number, main_win)
--   local current_line = vim.fn.line(".")
--   local target_line = current_line
--   for _, l in ipairs(lines) do
--     if current_line < l then
--       target_line = l
--       break
--     end
--   end
--   -- cycle
--   if current_line >= lines[#lines] then
--     target_line = lines[1]
--   end
--   vim.cmd(tostring(target_line))
-- end
--
-- function M.prev_file_comment(repo, number, main_win)
--   api.nvim_set_current_win(main_win)
--   local lines = M.get_file_comment_lines(repo, number, main_win)
--   local current_line = vim.fn.line(".")
--   local target_line = current_line
--   for _, l in ipairs(vim.fn.reverse(lines)) do
--     if current_line > l then
--       target_line = l
--       break
--     end
--   end
--   -- cycle
--   if current_line <= lines[1] then
--     target_line = lines[#lines]
--   end
--   vim.cmd(tostring(target_line))
-- end

function M.next_comment(repo, number, main_win)
  api.nvim_set_current_win(main_win)
  local qf = vim.fn.getqflist({idx = 0, size = 0})
  if qf.idx == qf.size then
    vim.cmd [[cfirst]]
  else
    vim.cmd [[cnext]]
  end
  M.show_reviewthread_qf_entry(repo, number, main_win)
end

function M.prev_comment(repo, number, main_win)
  api.nvim_set_current_win(main_win)
  local qf = vim.fn.getqflist({idx = 0})
  if qf.idx == 1 then
    vim.cmd [[clast]]
  else
    vim.cmd [[cprev]]
  end
  M.show_reviewthread_qf_entry(repo, number, main_win)
end

function M.add_changes_qf_mappings()
  vim.cmd [[nnoremap <silent><buffer>]q :lua require'octo.reviews'.next_change()<CR>]]
  vim.cmd [[nnoremap <silent><buffer>[q :lua require'octo.reviews'.prev_change()<CR>]]
  vim.cmd [[nnoremap <silent><buffer><C-c> :tabclose <BAR> :lua require'octo.reviews'.clean_fugitive_buffers()<CR>]]

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[wincmd p]]
end

function M.next_change()
  local qf = vim.fn.getqflist({idx = 0, size = 0})
  if qf.idx == qf.size then
    vim.cmd [[cfirst]]
  else
    vim.cmd [[cnext]]
  end
  M.diff_changes_qf_entry()
end

function M.prev_change()
  local qf = vim.fn.getqflist({idx = 0})
  if qf.idx == 1 then
    vim.cmd [[clast]]
  else
    vim.cmd [[cprev]]
  end
  M.diff_changes_qf_entry()
end

return M
