local octo = require "octo"
local writers = require "octo.writers"
local signs = require "octo.signs"
local util = require "octo.util"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local window = require "octo.window"
local format = string.format
local vim = vim
local api = vim.api
local json = {
  parse = vim.fn.json_decode
}

local M = {}

-- holds the comments for the current pending review
local _review_threads = {}
-- holds the id of the current pending review
local _review_id = -1
-- holds a cache of the changed files contents for the current pending review
local _review_files = {}

-- sets the height of the quickfix window
local qf_height = math.floor(vim.o.lines * 0.2)
if vim.g.octo_qf_height then
  if vim.g.octo_qf_height > 0 and vim.g.octo_qf_height < 1 then
    qf_height = math.floor(vim.o.lines * vim.g.octo_qf_height)
  elseif vim.g.octo_qf_height > 1 then
    qf_height = math.floor(vim.g.octo_qf_height)
  end
end

---
--- Changes
---
function M.populate_changes_qf(changes, opts)
  -- open a new tab so we can easily clean all the windows mess
  vim.cmd [[tabnew %]]

  -- populate qf
  local context = {
    left_commit = opts.baseRefOid,
    right_commit = opts.headRefOid,
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
      _review_files[change.path] = {}
      util.get_file_contents(opts.pull_request_repo, opts.baseRefOid, change.path, function(lines)
        _review_files[change.path].left_lines = lines
      end)
      util.get_file_contents(opts.pull_request_repo, opts.headRefOid, change.path, function(lines)
        _review_files[change.path].right_lines = lines
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

function M.diff_changes_qf_entry(target)
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
  local left_commit = qf.context.left_commit
  local right_commit = qf.context.right_commit
  local path = qf.items[qf.idx].module
  local repo = qf.context.pull_request_repo
  local number = qf.context.pull_request_number

  -- calculate valid comment ranges
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
  local left_bufname = format("octo://%s/pull/%d/file/LEFT/%s", repo, number, path)
  local left_bufnr = vim.fn.bufnr(left_bufname)
  if left_bufnr == -1 then
    left_bufnr = api.nvim_create_buf(true, true)
    api.nvim_buf_set_name(left_bufnr, left_bufname)
    api.nvim_buf_set_lines(left_bufnr, 0, -1, false, {"Loading ..."})
    api.nvim_buf_set_option(left_bufnr, "modifiable", false)
  end

  -- prepare right buffer
  local right_bufname = format("octo://%s/pull/%d/file/RIGHT/%s", repo, number, path)
  local right_bufnr = vim.fn.bufnr(right_bufname)
  if right_bufnr == -1 then
    right_bufnr = api.nvim_create_buf(true, true)
    api.nvim_buf_set_name(right_bufnr, right_bufname)
    api.nvim_buf_set_lines(right_bufnr, 0, -1, false, {"Loading ..."})
    api.nvim_buf_set_option(right_bufnr, "modifiable", false)
  end

  -- configure window layout and mappings
  api.nvim_set_current_win(right_win)
  api.nvim_win_set_buf(right_win, right_bufnr)
  M.add_changes_qf_mappings()
  vim.cmd(format("leftabove vert sbuffer %d", left_bufnr))
  local left_win = util.getwin4buf(left_bufnr)
  M.add_changes_qf_mappings()

  api.nvim_buf_set_var(right_bufnr, "OctoDiffProps", {
    diffSide = "RIGHT",
    commit = right_commit,
    qf_idx = qf.idx,
    qf_winid = qf.winid,
    path = qf.items[qf.idx].module,
    bufname = right_bufname,
    content_bufnr = right_bufnr,
    hunks = valid_hunks,
    comment_ranges = valid_right_ranges,
    alt_win = left_win,
    alt_bufnr = left_bufnr
  })

  api.nvim_buf_set_var(left_bufnr, "OctoDiffProps", {
    diffSide = "LEFT",
    commit = left_commit,
    qf_idx = qf.idx,
    qf_winid = qf.winid,
    path = path,
    bufname = left_bufname,
    content_bufnr = left_bufnr,
    hunks = valid_hunks,
    comment_ranges = valid_left_ranges,
    alt_win = right_win,
    alt_bufnr = right_bufnr
  })

  local write_diff_lines = function(lines, side)
    local bufnr, winnr
    if side == "right" then
      bufnr = right_bufnr
      winnr = right_win
      _review_files[path].right_lines = lines
    elseif side == "left" then
      bufnr = left_bufnr
      winnr = left_win
      _review_files[path].left_lines = lines
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
  if _review_files[path] and _review_files[path].right_lines and _review_files[path].left_lines then
    write_diff_lines(_review_files[path].right_lines, "right")
    write_diff_lines(_review_files[path].left_lines, "left")

    -- move cursor to comment if necessary
    if target and target.diffSide == "RIGHT" then
      api.nvim_set_current_win(right_win)
      api.nvim_win_set_cursor(right_win, {target.line, 1})
    elseif target and target.diffSide == "LEFT" then
      api.nvim_set_current_win(left_win)
      api.nvim_win_set_cursor(left_win, {target.line, 1})
    end
  else
    _review_files[path] = {}
    -- load left content
    util.get_file_contents(repo, left_commit, path, function(lines)
      write_diff_lines(lines, "left")

      -- move cursor to comment if necessary
      if target and target.diffSide == "LEFT" then
        api.nvim_set_current_win(left_win)
        api.nvim_win_set_cursor(left_win, {target.line, 1})
      end
    end)

    -- load right content
    util.get_file_contents(repo, right_commit, path, function(lines)
      write_diff_lines(lines, "right")

      -- move cursor to comment if necessary
      if target and target.diffSide == "RIGHT" then
        api.nvim_set_current_win(right_win)
        api.nvim_win_set_cursor(right_win, {target.line, 1})
      end
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
    -- check we are in a valid comment range
    local diff_hunk
    for i, range in ipairs(props.comment_ranges) do
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
    local comment_winid, comment_bufnr = window.create_centered_float({
      header = format("Add comment for %s (from %d to %d) [%s]", props.path, line1, line2, props.diffSide)
    })

    local bufname = format("%s:%d.%d", string.gsub(props.bufname, "/file/", "/comment/"), line1, line2)
    api.nvim_buf_set_name(comment_bufnr, bufname)
    api.nvim_buf_set_option(comment_bufnr, "syntax", "markdown")
    api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
    api.nvim_buf_set_var(comment_bufnr, "OctoDiffProps", props)

    if isSuggestion then
      local lines = api.nvim_buf_get_lines(props.content_bufnr, line1-1, line2, false)
      local suggestion = {"```suggestion"}
      vim.list_extend(suggestion, lines)
      table.insert(suggestion, "```")
      api.nvim_buf_set_lines(comment_bufnr, 0, -1, false, suggestion)
      api.nvim_buf_set_option(comment_bufnr, "modified", false)
    end

    -- change to insert mode
    api.nvim_set_current_win(comment_winid)
    vim.cmd [[normal G]]
    vim.cmd [[startinsert]]
  end
end

function M.edit_review_comment()
  -- check we are in an octo diff buffer
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if not status or not props then
    api.nvim_err_writeln("Not in Octo diff buffer")
    return
  end

  local threads = vim.tbl_values(_review_threads)
  for _, thread in ipairs(threads) do
    local cursor = api.nvim_win_get_cursor(0)
    if util.is_thread_placed_in_buffer(thread, bufnr) and thread.startLine <= cursor[1] and thread.line >= cursor[1] then

      -- create thread window and buffer
      local _, comment_bufnr = window.create_centered_float({
        header = format("Edit comment for %s (from %d to %d) [%s]", thread.path, thread.startLine, thread.line, props.diffSide)
      })

      local bufname = format("%s:%d.%d", string.gsub(props.bufname, "/file/", "/comment/"), thread.startLine, thread.line)
      api.nvim_buf_set_name(comment_bufnr, bufname)
      api.nvim_buf_set_option(comment_bufnr, "syntax", "markdown")
      api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
      props["id"] = thread.id
      api.nvim_buf_set_var(comment_bufnr, "OctoDiffProps", props)
      api.nvim_buf_set_lines(comment_bufnr, 0, -1, false, vim.split(thread.comments.nodes[1].body, "\n"))
      return
    end
  end
  api.nvim_err_writeln("No comment found at cursor line")
end

-- called when saving a review comment buffer
function M.save_review_comment()
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if status and props then

    -- extract comment body
    local bufname = api.nvim_buf_get_name(bufnr)
    local body = table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    local startLine, line = string.match(bufname, ".*:(%d+)%.(%d+)$")

    -- sync comment with GitHub
    local query, op
    if props.id then
      -- update comment in GitHub
      query = graphql("update_pull_request_review_comment_mutation", props.id, body)
      op = "update"
    else
      -- create new comment with GitHub
      op = "create"
      if startLine == line then
        query = graphql("add_pull_request_review_thread_mutation", _review_id, body, props.path, props.diffSide, line )
      else
        query = graphql("add_pull_request_review_multiline_thread_mutation", _review_id, body, props.path, props.diffSide, props.diffSide, startLine, line)
      end
    end
    gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            local resp = json.parse(output)

            if op == "create" then
              local thread = resp.data.addPullRequestReviewThread.thread
              if thread.startLine == vim.NIL then
                thread.startLine = thread.line
                thread.startDiffSide = thread.diffSide
              end

              -- update comment buffer props
              props.id = thread.id
              api.nvim_buf_set_var(bufnr, "OctoDiffProps", props)

              -- add new thread
              _review_threads[props.id] = thread

              --[[
              {
                id = first_comment.id,
                path = thread.path,
                startDiffSide = thread.startDiffSide,
                diffSide = thread.diffSide,
                diffHunk = first_comment.diffHunk,
                commit = first_comment.commit.abbreviatedOid,
                startLine = thread.startLine,
                line = thread.line,
                body = first_comment.body,
                author = first_comment.author,
                authorAssociation = first_comment.authorAssociation,
                viewerDidAuthor = first_comment.viewerDidAuthor,
                state = first_comment.state
              }
              ]]--
            end
          end
        end
      }
    )
  end
end

---
--- Review threads
---
function M.review_threads()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  local owner, name = util.split_repo(repo)
  local query = graphql("review_threads_query", owner, name, number)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          M.populate_reviewthreads_qf(repo, number, resp.data.repository.pullRequest.reviewThreads.nodes)
        end
      end
    }
  )
end

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
        table.insert(mods, "RESOLVED ")
      end
      if thread.isOutdated then
        table.insert(mods, "OUTDATED ")
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
  vim.cmd [[call matchadd("OctoNvimUser", "|\\s\\zs[^(]+\\ze\(")]]
  vim.cmd [[call matchadd("OctoNvimBubbleRed", "OUTDATED")]]
  vim.cmd [[call matchadd("OctoNvimBubbleGreen", "RESOLVED")]]

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
  local threads = api.nvim_win_get_var(main_win, "reviewthreads")
  local thread
  for _, t in ipairs(threads) do
    if reviewthread_id == t.id then
      thread = t
    end
  end

  -- prepare content buffer
  local content_bufname = format("octo://%s/pull/%d/file/%s/%s", repo, number, thread.diffSide, path)
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
    api.nvim_set_current_win(main_win)
    local ok = pcall(api.nvim_win_set_cursor, main_win, {row, 1})
    if not ok then
      api.nvim_err_writeln("Cannot move cursor to line " .. row)
    else
      vim.cmd [[normal! zz]]
    end

    -- highlight commented lines
    signs.unplace(content_bufnr)
    M.highlight_lines(content_bufnr, thread.startLine, thread.line)

  end)

  -- prepare comment buffer
  local comment_win = api.nvim_win_get_var(main_win, "comment_win")
  -- TODO: this will fail if user closes reviewthread window
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
    local main_comment = thread.comments.nodes[1]
    local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
    local end_line = thread.originalLine
    writers.write_review_thread_header(comment_bufnr, {
      path = thread.path,
      start_line = start_line,
      end_line = end_line,
      isOutdated = thread.isOutdated,
      isResolved = thread.isResolved
    })
    writers.write_diff_hunk(comment_bufnr, main_comment.diffHunk)

    -- write thread
    api.nvim_buf_set_var(comment_bufnr, "comments", {})
    for _, comment in ipairs(thread.comments.nodes) do
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
  api.nvim_buf_set_keymap(bufnr, "n", "<space>ce", [[<cmd>lua require'octo.reviews'.edit_review_comment()<CR>]], mapping_opts)
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

function M.start_review()
  local repo, number, pr = util.get_repo_number_pr()
  if not repo then
    return
  end

  _review_id = -1
  _review_threads = {}
  _review_files = {}

  -- start new review
  local query = graphql("start_review_mutation", pr.id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)

          _review_id = resp.data.addPullRequestReview.pullRequestReview.id

          local threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
          for _, thread in ipairs(threads) do
            if thread.startLine == vim.NIL then
              thread.startLine = thread.line
              thread.startDiffSide = thread.diffSide
            end
            _review_threads[thread.id] = thread
          end

          M.initiate_review(repo, number, pr)
        end
      end
    }
  )
end

function M.initiate_review(repo, number, pr)
  -- get changed files
  local url = format("repos/%s/pulls/%d/files", repo, number)
  gh.run(
    {
      args = {"api", url},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local results = json.parse(output)
          local changes = {}
          for _, result in ipairs(results) do
            local change = {
              path = result.filename,
              patch = result.patch,
              status = result.status,
              stats = format("+%d -%d ~%d", result.additions, result.deletions, result.changes)
            }
            table.insert(changes, change)
          end
          M.populate_changes_qf(
            changes,
            {
              pull_request_repo = repo,
              pull_request_number = number,
              pull_request_id = pr.id,
              baseRefOid = pr.baseRefOid,
              headRefOid = pr.headRefOid
            }
          )
        end
      end
    }
  )
end

function M.resume_review()
  local repo, number, pr = util.get_repo_number_pr()
  if not repo then
    return
  end
  -- start new review
  local owner, name = util.split_repo(repo)
  local query = graphql("pending_review_threads_query", owner, name, number)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          if #resp.data.repository.pullRequest.reviews.nodes == 0 then
            api.nvim_err_writeln("No pending reviews found")
            return
          end

          -- There can only be one pending review for a given user
          for _, review in ipairs(resp.data.repository.pullRequest.reviews.nodes) do
            if review.viewerDidAuthor then
              _review_id = review.id
              break
            end
          end

          if not _review_id then
            api.nvim_err_writeln("No pending reviews found for viewer")
            return
          end

          local threads = resp.data.repository.pullRequest.reviewThreads.nodes
          for _, thread in ipairs(threads) do
            if thread.startLine == vim.NIL then
              thread.startLine = thread.line
              thread.startDiffSide = thread.diffSide
            end
            _review_threads[thread.id] = thread
          end

          M.initiate_review(repo, number, pr)
        end
      end
    }
  )
end

function M.discard_review()
  local repo, number = util.get_repo_number_pr()
  if not repo then
    return
  end
  local owner, name = util.split_repo(repo)
  local query = graphql("pending_review_threads_query", owner, name, number)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          if #resp.data.repository.pullRequest.reviews.nodes == 0 then
            api.nvim_err_writeln("No pending reviews found")
            return
          end
          local review_id = resp.data.repository.pullRequest.reviews.nodes[1].id
          local delete_query = graphql("delete_pull_request_review_mutation", review_id)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", delete_query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  _review_id = -1
                  M.comments = {}
                  M.files= {}
                  print("[Octo] Pending review discarded")
                end
              end
            }
          )
        end
      end
    }
  )
end

function M.delete_pending_review_comment(comment)
  local query = graphql("delete_pull_request_review_comment_mutation", comment.id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(_)
        for _, thread in ipairs(_review_threads) do
          for _, c in ipairs(thread.comments.nodes) do
            if comment.id == c then
              _review_threads[thread.id] = nil
              break
            end
          end
        end
      end
    }
  )
end

function M.jump_to_pending_review_comment(comment)
  local qf = vim.fn.getqflist({items = 0})
  local idx
  for i, item in ipairs(qf.items) do
    if comment.path == item.module then
      idx = i
      break
    end
  end
  if idx then
    -- select qf item
    vim.fn.setqflist({}, 'r', {idx = idx })
    M.diff_changes_qf_entry({
      diffSide = comment.diffSide,
      startLine = comment.startLine,
      line = comment.line,
    })
  end
end

function M.update_pending_review_comment(comment)
  local qf = vim.fn.getqflist({context = 0})
  local repo = qf.context.pull_request_repo
  local number = qf.context.pull_request_number
  local _, comment_bufnr = window.create_centered_float({
    header = format("Edit comment for %s (from %d to %d) [%s]", comment.path, comment.startLine, comment.line, comment.diffSide)
  })
  local bufname = format("octo://%s/pull/%d/comment/%s/%s:%d.%d", repo, number, comment.diffSide, comment.path, comment.startLine, comment.line)
  api.nvim_buf_set_name(comment_bufnr, bufname)
  api.nvim_buf_set_option(comment_bufnr, "syntax", "markdown")
  api.nvim_buf_set_option(comment_bufnr, "buftype", "acwrite")
  api.nvim_buf_set_var(comment_bufnr, "OctoDiffProps", {
    id = comment.id
  })
  api.nvim_buf_set_lines(comment_bufnr, 0, -1, false, vim.split(comment.body, "\n"))
end

function M.submit_review()
  if _review_id == -1 then
    api.nvim_err_writeln("No review in progress")
    return
  end

  local winid, bufnr = window.create_centered_float({
    header = "Press <c-a> to approve, <c-m> to comment or <c-r> to request changes"
  })
  api.nvim_set_current_win(winid)
  api.nvim_buf_set_option(bufnr, "syntax", "markdown")

  local mapping_opts = {script = true, silent = true, noremap = true}
  api.nvim_buf_set_keymap(bufnr, "i", "<CR>", "<CR>", mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "q", format(":call nvim_win_close(%d, 1)<CR>", winid), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<esc>", format(":call nvim_win_close(%d, 1)<CR>", winid), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-c>", format(":call nvim_win_close(%d, 1)<CR>", winid), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-a>", ":lua require'octo.reviews'.do_submit_review('APPROVE')<CR>", mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-m>", ":lua require'octo.reviews'.do_submit_review('COMMENT')<CR>", mapping_opts)
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<C-r>",
    ":lua require'octo.reviews'.do_submit_review('REQUEST_CHANGES')<CR>",
    mapping_opts
  )
  vim.cmd [[normal G]]
  --vim.cmd [[startinsert]]
end

function M.do_submit_review(event)
  local bufnr = api.nvim_get_current_buf()
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body = util.escape_chars(vim.fn.trim(table.concat(lines, "\n")))
  local query = graphql("submit_pull_request_review_mutation", _review_id, event, body, {escape = false})
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print("[Octo] Review was submitted successfully!")
        end
      end
    }
  )
  M.close_review_tab()
end

function M.show_pending_comments()
  if _review_id == -1 then
    api.nvim_err_writeln("No review in progress")
    return
  end
  local threads = vim.tbl_values(_review_threads)
  local filtered_threads = {}
  for _, thread in ipairs(threads) do
    local first_comment = thread.comments.nodes[1]
    local review = first_comment.pullRequestReview
    if review.state == "PENDING" and not util.is_blank(vim.fn.trim(first_comment.body)) then
      table.insert(filtered_threads, thread)
    end
  end
  if #filtered_threads == 0 then
    api.nvim_err_writeln("No pending comments found")
    return
  else
    require"octo.menu".pending_comments(filtered_threads)
  end
end

function M.clear_review_threads()
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if not status or not props then
    return
  end
  local diff_bufnr = props.alt_bufnr
  local current_alt_bufnr = api.nvim_win_get_buf(props.alt_win)
  if current_alt_bufnr ~= diff_bufnr then
    api.nvim_win_set_buf(props.alt_win, diff_bufnr)
    local bufname = api.nvim_buf_get_name(current_alt_bufnr)
    if vim.startswith(bufname, "octo://thread") then
      api.nvim_buf_delete(current_alt_bufnr, {force = true})
    end
  end
end

function M.show_review_threads()
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if not status or not props then
    return
  end
  local threads = vim.tbl_values(_review_threads)
  local cursor = api.nvim_win_get_cursor(0)
  local threads_at_cursor = {}
  for _, thread in ipairs(threads) do
    if util.is_thread_placed_in_buffer(thread, bufnr) and thread.startLine <= cursor[1] and thread.line >= cursor[1] then
      table.insert(threads_at_cursor, thread)
    end
  end

  if #threads_at_cursor == 0 then
    return
  end

  -- window.create_thread_popup(props.alt_win, thread)
  local thread_bufnr = api.nvim_create_buf(false, true)
  local thread_bufname = format("octo://thread")
  api.nvim_buf_set_name(thread_bufnr, thread_bufname)

  for _, thread in ipairs(threads_at_cursor) do
    local thread_start, thread_end
    for _, comment in ipairs(thread.comments.nodes) do

      -- review thread header
      if comment.replyTo == vim.NIL then
        local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
        local end_line = thread.originalLine
        writers.write_review_thread_header(bufnr, {
          path = thread.path,
          start_line = start_line,
          end_line = end_line,
          isOutdated = thread.isOutdated,
          isResolved = thread.isResolved,
        })

        -- write snippet
        thread_start, thread_end = writers.write_diff_hunk(thread_bufnr, comment.diffHunk, nil, start_line, end_line, thread.diffSide)
      end

      api.nvim_buf_set_var(thread_bufnr, "comments", {})
      local comment_start, comment_end = writers.write_comment(thread_bufnr, comment, "PullRequestReviewComment")
      thread_end = comment_end
    end
  end

  if api.nvim_win_is_valid(props.alt_win) then
    api.nvim_win_set_buf(props.alt_win, thread_bufnr)
  else
    api.nvim_err_writeln("[Octo] Cannot find diff window")
  end
end

function M.place_comment_signs()
  local bufnr = api.nvim_get_current_buf()
  signs.unplace(bufnr)
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if status and props then
    for _, range in ipairs(props.comment_ranges) do
      for line = range[1], range[2] do
        signs.place("octo_comment_range", bufnr, line - 1)
      end
    end
    local threads = vim.tbl_values(_review_threads)
    for _, thread in ipairs(threads) do
      if util.is_thread_placed_in_buffer(thread, bufnr) then
        for line = thread.startLine, thread.line do
          local sign = "octo_thread"

          if thread.isResolved then
            sign = sign .. "_resolved"
          elseif thread.isOudated then
            sign = sign .. "_outdated"
          end

          for _, comment in ipairs(thread.comments.nodes) do
            if comment.state == "PENDING" then
              sign = sign .. "_pending"
              break
            end
          end

          signs.place(sign, bufnr, line - 1)
        end
      end
    end
  end
end

return M
