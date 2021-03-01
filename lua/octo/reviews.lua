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
M.review_files = {}

local qf_height = vim.g.octo_qf_height or math.floor(vim.o.lines * 0.2)

---
--- Changes
---

function M.populate_changes_qf(changes, opts)
  -- open a new tab so we can easily clean all the windows mess
  vim.cmd [[tabnew %]]

  -- populate qf
  local context = {
    left_sha = opts.baseRefSHA,
    right_sha = opts.headRefSHA,
    pull_request_id = opts.pull_request_id,
    pull_request_repo = opts.pull_request_repo,
    pull_request_number = opts.pull_request_number
  }
  local items = {}
  local ctxitems = {}
  for _, change in ipairs(changes) do
    local item = {
      module = change.path,
      text = change.stats,
      pattern = change.status
    }
    table.insert(items, item)

    local ctxitem = {
      patch = change.patch
    }
    table.insert(ctxitems, ctxitem)

    -- prefetch changed files
    util.set_timeout(5000, vim.schedule_wrap(function()
      M.review_files[change.path] = {}
      util.get_file_contents(opts.pull_request_repo, opts.baseRefSHA, change.path, function(lines)
        M.review_files[change.path].left_lines = lines
      end)
      util.get_file_contents(opts.pull_request_repo, opts.headRefSHA, change.path, function(lines)
        M.review_files[change.path].right_lines = lines
      end)
    end))
  end
  context.items = ctxitems

  vim.fn.setqflist({}, "r", {context = context, items = items})

  M.diff_changes_qf_entry()

  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[nnoremap <silent><buffer> <CR> <CR><BAR>:lua require'octo.reviews'.diff_changes_qf_entry()<CR>]]
  M.add_changes_qf_mappings()
  vim.cmd [[wincmd p]]
end

function M.diff_changes_qf_entry()
  -- cleanup content buffers and windows
  vim.cmd [[cclose]]
  vim.cmd [[silent! only]]

  local right_win = api.nvim_get_current_win()

  -- select qf entry
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[nnoremap <silent><buffer> <CR> <CR><BAR>:lua require'octo.reviews'.diff_changes_qf_entry()<CR>]]
  M.add_changes_qf_mappings()
  vim.cmd [[cc]]

  local qf = vim.fn.getqflist({context = 0, idx = 0, items = 0, winid = 0})
  local ctxitem = qf.context.items[qf.idx]
  local left_sha = qf.context.left_sha
  local right_sha = qf.context.right_sha
  local path = qf.items[qf.idx].module
  local repo = qf.context.pull_request_repo
  local number = qf.context.pull_request_number

  -- calculate valid ranges
  local valid_left_ranges = {}
  local valid_right_ranges = {}
  local valid_hunks = {}
  local hunk_strings = vim.split(ctxitem.patch:gsub("^@@", ""), "\n@@")
  for _, hunk in ipairs(hunk_strings) do
    local header = vim.split(hunk, "\n")[1]
    local found, _, left_start, left_length, right_start, right_length =
      string.find(header, "^%s%-(%d+),(%d+)%s%+(%d+),(%d+)%s@@")
    if found then
      table.insert(valid_hunks, hunk)
      table.insert(valid_left_ranges, {tonumber(left_start), left_start + left_length - 1})
      table.insert(valid_right_ranges, {tonumber(right_start), right_start + right_length - 1})
    end
  end

  -- prepare left buffer
  local left_bufname = format("octo://%s/pull/%d/file/%s/%s", repo, number, left_sha:sub(0,7), path)
  local left_bufnr = vim.fn.bufnr(left_bufname)
  if left_bufnr == -1 then
    left_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(left_bufnr, left_bufname)
    api.nvim_buf_set_lines(left_bufnr, 0, -1, false, {"Loading ..."})
    api.nvim_buf_set_option(left_bufnr, "modifiable", false)
  end
  api.nvim_buf_set_var(left_bufnr, "OctoDiffProps", {
    side = "LEFT",
    sha = left_sha,
    qf_idx = qf.idx,
    qf_winid = qf.winid,
    path = path,
    bufname = left_bufname,
    content_bufnr = left_bufnr,
    hunks = valid_hunks,
    ranges = valid_left_ranges,
  })

  -- prepare right buffer
  local right_bufname = format("octo://%s/pull/%d/file/%s/%s", repo, number, right_sha:sub(0,7), path)
  local right_bufnr = vim.fn.bufnr(right_bufname)
  if right_bufnr == -1 then
    right_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(right_bufnr, right_bufname)
    api.nvim_buf_set_lines(right_bufnr, 0, -1, false, {"Loading ..."})
    api.nvim_buf_set_option(right_bufnr, "modifiable", false)
  end
  api.nvim_buf_set_var(right_bufnr, "OctoDiffProps", {
    side = "RIGHT",
    sha = right_sha,
    qf_idx = qf.idx,
    qf_winid = qf.winid,
    path = qf.items[qf.idx].module,
    bufname = right_bufname,
    content_bufnr = right_bufnr,
    hunks = valid_hunks,
    ranges = valid_right_ranges,
  })

  -- configure window layout and mappings
  api.nvim_set_current_win(right_win)
  api.nvim_win_set_buf(right_win, right_bufnr)
  M.add_changes_qf_mappings()
  vim.cmd(format("leftabove vert sbuffer %d", left_bufnr))
  local left_win = util.getwin4buf(left_bufnr)
  M.add_changes_qf_mappings()

  local write_diff_lines = function(lines, side)
    local bufnr, winnr
    if side == "right" then
      bufnr = right_bufnr
      winnr = right_win
      M.review_files[path].right_lines = lines
    elseif side == "left" then
      bufnr = left_bufnr
      winnr = left_win
      M.review_files[path].left_lines = lines
    end
    api.nvim_buf_set_option(bufnr, "modifiable", true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    api.nvim_buf_set_option(bufnr, "modifiable", false)
    api.nvim_set_current_win(winnr)
    vim.cmd [[filetype detect]]
    vim.cmd [[doau BufEnter]]
    vim.cmd [[diffthis]]
    vim.cmd [[normal! gg]c]]
  end

  -- load diff buffer contents
  if M.review_files[path] and M.review_files[path].right_lines and M.review_files[path].left_lines then
    write_diff_lines(M.review_files[path].right_lines, "right")
    write_diff_lines(M.review_files[path].left_lines, "left")
  else
    M.review_files[path] = {}
    -- load left content
    util.get_file_contents(repo, left_sha, path, function(lines)
      write_diff_lines(lines, "left")
    end)

    -- load right content
    util.get_file_contents(repo, right_sha, path, function(lines)
      write_diff_lines(lines, "right")
    end)
  end
end

function M.add_review_comment(isSuggestion)
  -- get visual selected line range
  local line1, line2
  if vim.fn.getpos("'<")[2] == vim.fn.getcurpos()[2] then
    line1 = vim.fn.getpos("'<")[2]
    line2 = vim.fn.getpos("'>")[2]
  else
    line1 = vim.fn.getcurpos()[2]
    line2 = vim.fn.getcurpos()[2]
  end

  -- check we are in an octo diff buffer
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

    -- create comment window and buffer
    local comment_winid, comment_bufnr = util.create_popup({
      header = format("Comment for %s (from %d to %d) [%s]", props.path, line1, line2, props.side)
    })
    api.nvim_set_current_win(comment_winid)
    api.nvim_buf_set_option(comment_bufnr, "syntax", "markdown")

    local bufname = format("%s:%d.%d", string.gsub(props.bufname, "/file/", "/comment/"), line1, line2)
    api.nvim_buf_set_name(comment_bufnr, bufname)
    api.nvim_buf_set_option(comment_bufnr, "syntax", "markdown")
    api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
    api.nvim_buf_set_var(comment_bufnr, "OctoDiffProps", props)
    api.nvim_win_set_var(props.qf_winid, "comment_winid", comment_winid)

    if isSuggestion then
      local lines = api.nvim_buf_get_lines(props.content_bufnr, line1-1, line2, false)
      local suggestion = {"```suggestion"}
      vim.list_extend(suggestion, lines)
      table.insert(suggestion, "```")
      api.nvim_buf_set_lines(comment_bufnr, 0, -1, false, suggestion)
      api.nvim_buf_set_option(comment_bufnr, "modified", false)
    end

    -- change to insert mode
    vim.cmd [[normal G]]
    vim.cmd [[startinsert]]

    -- create new comment
    local comment = {
      key = bufname,
      path =props.path,
      side = props.side,
      diff_hunk = diff_hunk,
      sha = props.sha,
      qf_idx = props.qf_idx,
      qf_winid = props.qf_winid,
      comment_bufnr = comment_bufnr,
      comment_winid = comment_winid,
      content_bufnr = bufnr,
      line1 = line1,
      line2 = line2,
      body = ""
    }

    -- add comment to list of pending comments
    M.review_comments[bufname] = comment
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
    if not util.is_blank(comment.body) then
      -- highlight commented lines
      M.highlight_lines(comment.content_bufnr, comment.line1, comment.line2)
    end
  end
end

---
--- Review threads
---

function M.populate_reviewthreads_qf(repo, number, reviewthreads)
  local items = {}
  local ctxitems = {}
  local qf = vim.fn.getqflist({winid = 0})
  local qf_width = vim.fn.winwidth(qf.winid) * 0.4

  local process_threads = function(threads)
    for _, thread in ipairs(threads) do
      local first_comment = thread.comments.nodes[1]
      local mods = {}
      if thread.isResolved then
        table.insert(mods, "RESOLVED")
      end
      if thread.isOutdated then
        table.insert(mods, "OUTDATED")
      end
      local comment_id = util.graph2rest(first_comment.id)
      local lnum = thread.line
      if not lnum or lnum == vim.NIL then
        lnum = thread.originalLine
      end
      table.insert(
        ctxitems,
        {
          commit = first_comment.commit.oid
        }
      )
      table.insert(
        items,
        {
          module = thread.path,
          lnum = lnum,
          text = format(
            "%s (%s) %s%s...",
            first_comment.author.login,
            string.lower(first_comment.authorAssociation),
            table.concat(mods, " "),
            string.sub(vim.split(first_comment.body, "\n")[1], 0, qf_width)
          ),
          pattern = format("%s/%s", thread.id, comment_id)
        }
      )
    end
  end

  local open_threads =
    vim.tbl_filter(
    function(item)
      return not item.isResolved and not item.isOutdated
    end,
    reviewthreads
  )
  local outdated_not_resolved_threads =
    vim.tbl_filter(
    function(item)
      return item.isOutdated and not item.isResolved
    end,
    reviewthreads
  )
  local resolved_threads =
    vim.tbl_filter(
    function(item)
      return item.isResolved
    end,
    reviewthreads
  )

  -- add the unresolved threads first
  process_threads(open_threads)
  process_threads(outdated_not_resolved_threads)
  process_threads(resolved_threads)

  if #items == 0 then
    api.nvim_err_writeln("No comments found")
    return
  end

  -- populate qf
  vim.fn.setqflist({}, "r", {context = {items = ctxitems} , items = items})

  -- new tab to hold the main, qf and comment windows
  if true then
    vim.cmd(format("tabnew %s", items[1].filename))
  end

  local main_win = api.nvim_get_current_win()

  -- save review comments in main window var
  api.nvim_win_set_var(main_win, "reviewthreads", reviewthreads)

  -- open qf
  vim.cmd(format("%dcopen", qf_height))
  local qf_win = vim.fn.getqflist({winid = 0}).winid

  -- highlight qf entries
  vim.cmd [[call matchadd("Comment", "\(.*\)")]]
  vim.cmd [[call matchadd("OctoNvimCommentUser", "|\\s\\zs[^(]+\\ze\(")]]
  vim.cmd [[call matchadd("OctoNvimBubbleRed", "OUTDATED")]]
  vim.cmd [[call matchadd("OctoNvimBubbleGreen", "RESOLVED")]]
  vim.cmd [[call matchadd("OctoNvimBubbleDelimiter", "")]]
  vim.cmd [[call matchadd("OctoNvimBubbleDelimiter", "")]]

  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
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
  --vim.cmd [[cc]]

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

  -- select qf entry
  vim.cmd [[cc]]

  local qf = vim.fn.getqflist({context = 0, idx = 0, items = 0, winid = 0})

  local idx = qf.idx or 0
  local items = qf.items or {}
  local context = qf.context or {}
  local path = qf.items[idx].module
  local commit = context.items[idx].commit

  -- get comment details
  local selected_item = items[idx]
  local ids = selected_item.pattern
  local reviewthread_id = vim.split(ids, "/")[1]
  local comment_id = vim.split(ids, "/")[2]

  -- get cached thread
  local reviewthreads = api.nvim_win_get_var(main_win, "reviewthreads")
  local reviewthread
  for _, thread in ipairs(reviewthreads) do
    if reviewthread_id == thread.id then
      reviewthread = thread
    end
  end

  -- prepare content buffer
  local content_bufname = format("octo://%s/pull/%d/file/%s/%s", repo, number, commit:sub(0,7), path)
  local content_bufnr = vim.fn.bufnr(content_bufname)
  if content_bufnr == -1 then
    content_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(content_bufnr, content_bufname)
    api.nvim_buf_set_lines(content_bufnr, 0, -1, false, {"Loading ..."})
  end

  api.nvim_set_current_win(main_win)
  api.nvim_win_set_buf(main_win, content_bufnr)
  M.add_reviewthread_qf_mappings(repo, number, main_win)

  util.get_file_contents(repo, commit, path, function(lines)
    api.nvim_buf_set_option(content_bufnr, "modifiable", true)
    api.nvim_buf_set_lines(content_bufnr, 0, -1, false, lines)
    api.nvim_buf_set_option(content_bufnr, "modifiable", false)
    api.nvim_set_current_win(main_win)
    vim.cmd [[filetype detect]]

    -- go to comment line
    local row = (selected_item.lnum) or 1
    local ok = pcall(api.nvim_win_set_cursor, main_win, {row, 1})
    if not ok then
      api.nvim_err_writeln("Cannot move cursor to line " .. row)
    else
      vim.cmd [[normal! zz]]
    end

    -- highlight commented lines
    api.nvim_buf_clear_namespace(content_bufnr, constants.OCTO_HIGHLIGHT_NS, 0, -1)
    signs.unplace(content_bufnr)
    M.highlight_lines(content_bufnr, reviewthread.startLine, reviewthread.line)

  end)

  -- prepare comment buffer
  local comment_win = api.nvim_win_get_var(main_win, "comment_win")
  api.nvim_set_current_win(comment_win)

  local comment_bufname = format("octo://%s/pull/%d/reviewthread/%s/comment/%s", repo, number, reviewthread_id, comment_id)
  local comment_bufnr = vim.fn.bufnr(comment_bufname)
  if comment_bufnr > -1 then
    api.nvim_win_set_buf(comment_win, comment_bufnr)
  else
    comment_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_var(comment_bufnr, "repo", repo)
    api.nvim_buf_set_var(comment_bufnr, "number", number)
    api.nvim_buf_set_option(comment_bufnr, "syntax", "markdown")
    api.nvim_buf_set_option(comment_bufnr, "filetype", "octo_reviewthread")
    api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
    api.nvim_buf_set_name(comment_bufnr, comment_bufname)
    api.nvim_win_set_buf(comment_win, comment_bufnr)

    -- add mappings to the comment window buffer
    M.add_reviewthread_qf_mappings(repo, number, main_win)
    octo.apply_buffer_mappings(comment_bufnr, "reviewthread")

    -- write diff hunk
    local main_comment = reviewthread.comments.nodes[1]
    local start_line = reviewthread.originalStartLine ~= vim.NIL and reviewthread.originalStartLine or reviewthread.originalLine
    local end_line = reviewthread.originalLine
    writers.write_review_thread_header(comment_bufnr, {
      path = reviewthread.path,
      start_line = start_line,
      end_line = end_line,
      isOutdated = reviewthread.isOutdated,
      isResolved = reviewthread.isResolved
    })
    writers.write_commented_lines(comment_bufnr, main_comment.diffHunk, reviewthread.diffSide, start_line, end_line)

    -- write thread
    api.nvim_buf_set_var(comment_bufnr, "comments", {})
    for _, comment in ipairs(reviewthread.comments.nodes) do
      writers.write_comment(comment_bufnr, comment, "PullRequestReviewComment")
    end
  end

  -- show comment buffer signs
  signs.render_signcolumn(comment_bufnr)

  -- autocmds
  vim.cmd [[ augroup octo_reviewthread_autocmds ]]
  vim.cmd [[ au! * <buffer> ]]
  vim.cmd [[ au TextChanged <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ au TextChangedI <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ augroup END ]]
end

function M.highlight_lines(bufnr, startLine, endLine)
  if not endLine then return end
  startLine = startLine or endLine
  for line = startLine, endLine do
    --api.nvim_buf_add_highlight(bufnr, constants.OCTO_HIGHLIGHT_NS, "OctoNvimCommentLine", line - 1, 0, -1)
    signs.place("octo_comment", bufnr, line - 1)
  end
end

-- MAPPINGS
function M.add_reviewthread_qf_mappings(repo, number, main_win)
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
  vim.cmd [[silent! tabclose]]
end

function M.add_changes_qf_mappings(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local mapping_opts = {silent = true, noremap = true}
  api.nvim_buf_set_keymap(bufnr, "n", "]q", [[<cmd>lua require'octo.reviews'.next_change()<CR>]], mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "[q", [[<cmd>lua require'octo.reviews'.prev_change()<CR>]], mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-c>", [[<cmd>lua require'octo.reviews'.close_review_tab()<CR>]], mapping_opts)
  vim.cmd [[nnoremap <space>ca :OctoAddReviewComment<CR>]]
  vim.cmd [[vnoremap <space>ca :OctoAddReviewComment<CR>]]
  vim.cmd [[nnoremap <space>sa :OctoAddReviewSuggestion<CR>]]
  vim.cmd [[vnoremap <space>sa :OctoAddReviewSuggestion<CR>]]

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
    if util.is_blank(vim.fn.trim(c.body)) then goto continue end
    if c.line1 == c.line2 then
      table.insert(
        comments,
        format('{body:"%s", line:%d, path:"%s", side:%s}', util.escape_chars(c.body), c.line1, c.path, c.side)
      )
    else
      table.insert(
        comments,
        format(
          '{body:"%s", startLine:%d, line:%d, path:"%s", startSide:%s, side:%s}',
          util.escape_chars(c.body),
          c.line1,
          c.line2,
          c.path,
          c.side,
          c.side
        )
      )
    end
    ::continue::
  end
  comments = table.concat(comments, ", ")

  local qf = vim.fn.getqflist({context = 0})
  local pull_request_id = qf.context.pull_request_id
  local query = graphql("submit_review_mutation", pull_request_id, event, text, comments, {escape = false})
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print("Submitted!")
        end
      end
    }
  )
  M.close_review_tab()
end

return M
