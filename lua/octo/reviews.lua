local octo = require "octo"
local writers = require "octo.writers"
local signs = require "octo.signs"
local util = require "octo.util"
local constants = require "octo.constants"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local format = string.format
local vim = vim
local api = vim.api

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

  qf.context.pull_request_id = opts.pull_request_id

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
  local qf = vim.fn.getqflist({context = 0, items = 0})
  print(vim.inspect(qf))
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
      local valid_hunks = {}
      local hunk_strings = vim.split(ctxitem.patch, "\n@@")
      for _, hunk in ipairs(hunk_strings) do
        local header = vim.split(hunk, "\n")[1]
        local found, _, left_start, left_length, right_start, right_length = string.find(header, "@@%s%-(%d+),(%d+)%s%+(%d+),(%d+)%s@@")
        if found then
          table.insert(valid_hunks, hunk)
          table.insert(valid_left_ranges, {tonumber(left_start), left_start + left_length - 1})
          table.insert(valid_right_ranges, {tonumber(right_start), right_start + right_length - 1})
        end
      end

      -- set diff info as buf vars
      local left_props = {
        side = "LEFT",
        sha = left_sha,
        hunks = valid_hunks,
        qf_idx = qf.idx,
        qf_winid = qf.winid,
        ranges = valid_left_ranges,
        path = qf.items[qf.idx].module,
        bufname = left_bufname
      }
      local right_props = {
        side = "RIGHT",
        sha = right_sha,
        hunks = valid_hunks,
        qf_idx = qf.idx,
        qf_winid = qf.winid,
        ranges = valid_right_ranges,
        path = qf.items[qf.idx].module,
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

    -- check we are in a valid range
    local diff_hunk
    for i, range in ipairs(props.ranges) do
      if range[1] <= line1 and range[2] >= line2 then
        diff_hunk = props.hunks[i]
        break
      end
    end
    if not diff_hunk then
      api.nvim_err_writeln("Cannot place comments outside diff hunks")
      return
    end

    -- create new buffer
    local comment_bufnr = api.nvim_create_buf(false, true)

    -- check if there is a comment win already open
    local _, comment_winid = pcall(api.nvim_win_get_var, props.qf_winid, "comment_winid")
    if tonumber(comment_winid) and api.nvim_win_is_valid(comment_winid) then
      -- move to comment win
      api.nvim_win_set_buf(comment_winid, comment_bufnr)
      api.nvim_set_current_win(comment_winid)
    else
      -- move to qf win
      api.nvim_set_current_win(props.qf_winid)

      -- create new win and show comment bufnr
      vim.cmd(format("rightbelow vert sbuffer %d", comment_bufnr))

      -- store comment win id
      comment_winid = api.nvim_get_current_win()
      api.nvim_win_set_var(props.qf_winid, "comment_winid", comment_winid)
    end

    -- add mappings to comment buffer
    M.add_changes_qf_mappings()

    -- header
    local header_vt = {
      {format("%s", props.path), "OctoNvimDetailsValue"},
      {" ["},
      {format("%s", props.side), "OctoNvimDetailsLabel"},
      {"] ("},
      {format("%d,%d", line1, line2), "OctoNvimDetailsValue"},
      {")"}
    }
    writers.write_block({"", "", ""}, {bufnr = comment_bufnr, mark = false, line = 1})
    api.nvim_buf_set_virtual_text(comment_bufnr, constants.OCTO_TITLE_VT_NS, 0, header_vt, {})

    -- change to insert mode
    vim.cmd [[normal G]]
    vim.cmd [[startinsert]]

    local bufname = format("octo_comment://%s.%d.%d", string.gsub(props.bufname, "fugitive://", ""), line1, line2)

    -- create new comment
    local comment = {
      key = bufname,
      path = vim.split(props.path, ":")[2],
      side = props.side,
      diff_hunk = diff_hunk,
      sha = props.sha,
      qf_idx = props.qf_idx,
      qf_winid = props.qf_winid,
      comment_bufnr = comment_bufnr,
      comment_winid = comment_winid,
      line1 = line1,
      line2 = line2,
      body = ""
    }

    -- add comment to list of pending comments
    M.review_comments[bufname] = comment

    -- configure comment buffer
    api.nvim_buf_set_var(comment_bufnr, "OctoDiffProps", props)
    api.nvim_buf_set_option(comment_bufnr, "filetype", "octo_reviewcomment")
    api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
    api.nvim_buf_set_name(comment_bufnr, bufname)

    -- highlight
    M.highlight_lines(bufnr, line1, line2)
  end
end

function M.save_review_comment()
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if status and props then
    local bufname = api.nvim_buf_get_name(bufnr)
    local comment = M.review_comments[bufname]
    local body = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    comment.body = vim.fn.trim(body)
    M.review_comments[bufname] = comment
    api.nvim_buf_set_option(bufnr, "modified", false)
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

  -- TODO: improve it
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

function M.close_review_tab()

  -- close fugitive buffers
  M.clean_fugitive_buffers()

  -- close review comment buffers
  local tabpage = api.nvim_get_current_tabpage()
  for _, w in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if api.nvim_win_is_valid(w) then
      local bufnr = api.nvim_win_get_buf(w)
      if api.nvim_buf_get_option(bufnr, "filetype") == "octo_reviewcomment" then
        vim.cmd(format("bdelete! %d", bufnr))
      end
    end
  end
end

function M.add_changes_qf_mappings()
  vim.cmd [[nnoremap <silent><buffer>]q :lua require'octo.reviews'.next_change()<CR>]]
  vim.cmd [[nnoremap <silent><buffer>[q :lua require'octo.reviews'.prev_change()<CR>]]
  vim.cmd [[nnoremap <silent><buffer><C-c> :tabclose <BAR> :lua require'octo.reviews'.close_review_tab()<CR>]]

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

function M.submit_review(event)

  local bufnr = api.nvim_get_current_buf()
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = util.escape_chars(vim.fn.trim(table.concat(lines, "\n")))

  local comments = {}
  for _, c in ipairs(vim.tbl_values(M.review_comments)) do
    if c.line1 == c.line2 then
      table.insert(comments, format("{body:\"%s\", line:%d, path:\"%s\", side:%s}", util.escape_chars(c.body), c.line1, c.path, c.side))
    else
      table.insert(comments, format("{body:\"%s\", startLine:%d, line:%d, path:\"%s\", startSide:%s, side:%s}", util.escape_chars(c.body), c.line1, c.line2, c.path, c.side, c.side))
    end
  end
  comments = table.concat(comments, ", ")

  local qf = vim.fn.getqflist({context = 0})
  local pull_request_id = qf.context.pull_request_id
  local query = format(graphql.submit_review_mutation, pull_request_id, event, text, comments)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print(output)
        end
        api.nvim_win_close(0, true)
      end
    }
  )

--"message": "Start line must precede the end line."
--there is a line mismatch, comments are not exactly placed on the specified lines, at least for Left side
--its like the left side lines are mapped to the right ones. so 721 and 723 on the lhs are mapped to 723 to 725 on the rhs. so placing a comment on 721-725 LEFT get the comment placed on 723-725 LEFT

end

return M
