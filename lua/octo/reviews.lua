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

local _review_id = -1
local _review_threads = {}
local _review_files = {}

function M.get_review_id()
  return _review_id
end

function M.set_review_id(id)
  _review_id = id
end

-- sets the height of the quickfix window
local qf_height = math.floor(vim.o.lines * 0.2)
if octo.settings.qf_height then
  if octo.settings.qf_height > 0 and octo.settings.qf_height < 1 then
    qf_height = math.floor(vim.o.lines * octo.settings.qf_height)
  elseif octo.settings.qf_height > 1 then
    qf_height = math.floor(octo.settings.qf_height)
  end
end

---
--- Changes
---
function M.populate_qf(changes, opts)
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

  M.update_qf()

  M.select_qf_entry()

  -- bind <CR> for current quickfix window to properly set up diff split layout after selecting an item
  -- there's probably a better way to map this without changing the window
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[nnoremap <silent><buffer> <CR> <CR><BAR>:lua require'octo.reviews'.select_qf_entry()<CR>]]
  M.add_review_mappings()
  vim.cmd [[wincmd p]]
end

function M.select_qf_entry(target)
  -- cleanup content buffers and windows
  vim.cmd [[cclose]]
  vim.cmd [[silent! only]]

  local right_win = api.nvim_get_current_win()

  -- select qf entry
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[nnoremap <silent><buffer> <CR> <CR><BAR>:lua require'octo.reviews'.select_qf_entry()<CR>]]
  M.add_review_mappings()
  vim.cmd [[cc]]

  local qf = vim.fn.getqflist({context = 0, idx = 0, items = 0, winid = 0})
  local ctxitem = qf.context.items[qf.idx]
  local left_commit = qf.context.left_commit
  local right_commit = qf.context.right_commit
  local path = qf.items[qf.idx].module
  local repo = qf.context.pull_request_repo
  local number = qf.context.pull_request_number

  if not ctxitem or ctxitem == vim.NIL or not ctxitem.patch then
    return
  end

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
    left_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(left_bufnr, left_bufname)
    api.nvim_buf_set_lines(left_bufnr, 0, -1, false, {"Loading ..."})
    api.nvim_buf_set_option(left_bufnr, "modifiable", false)
  end

  -- prepare right buffer
  local right_bufname = format("octo://%s/pull/%d/file/RIGHT/%s", repo, number, path)
  local right_bufnr = vim.fn.bufnr(right_bufname)
  if right_bufnr == -1 then
    right_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(right_bufnr, right_bufname)
    api.nvim_buf_set_lines(right_bufnr, 0, -1, false, {"Loading ..."})
    api.nvim_buf_set_option(right_bufnr, "modifiable", false)
  end

  -- configure window layout and mappings
  api.nvim_set_current_win(right_win)
  api.nvim_win_set_buf(right_win, right_bufnr)
  M.add_review_mappings()
  vim.cmd(format("leftabove vert sbuffer %d", left_bufnr))
  local left_win = util.getwin4buf(left_bufnr)
  M.add_review_mappings()

  api.nvim_buf_set_var(right_bufnr, "OctoDiffProps", {
    diffSide = "RIGHT",
    commit = right_commit,
    -- qf_idx = qf.idx,
    -- qf_winid = qf.winid,
    path = qf.items[qf.idx].module,
    bufname = right_bufname,
    content_bufnr = right_bufnr,
    hunks = valid_hunks,
    comment_ranges = valid_right_ranges,
    alt_win = left_win,
    alt_bufnr = left_bufnr,
    repo = repo,
    number = number
  })

  api.nvim_buf_set_var(left_bufnr, "OctoDiffProps", {
    diffSide = "LEFT",
    commit = left_commit,
    -- qf_idx = qf.idx,
    -- qf_winid = qf.winid,
    path = path,
    bufname = left_bufname,
    content_bufnr = left_bufnr,
    hunks = valid_hunks,
    comment_ranges = valid_left_ranges,
    alt_win = right_win,
    alt_bufnr = right_bufnr,
    repo = repo,
    number = number
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

function M.close_review_tab()
  vim.cmd [[silent! tabclose]]
end

function M.add_review_mappings(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local mapping_opts = {silent = true, noremap = true}
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    octo.settings.mappings.next_changed_file,
    [[<cmd>lua require'octo.reviews'.next_change()<CR>]],
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    octo.settings.mappings.prev_changed_file,
    [[<cmd>lua require'octo.reviews'.prev_change()<CR>]],
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    octo.settings.mappings.next_thread,
    [[<cmd>lua require'octo.reviews'.next_thread()<CR>]],
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    octo.settings.mappings.prev_thread,
    [[<cmd>lua require'octo.reviews'.prev_thread()<CR>]],
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    octo.settings.mappings.close_tab,
    [[<cmd>lua require'octo.reviews'.close_review_tab()<CR>]],
    mapping_opts
  )
  vim.cmd(format("nnoremap %s :OctoAddReviewComment<CR>", octo.settings.mappings.add_comment))
  vim.cmd(format("vnoremap %s :OctoAddReviewComment<CR>", octo.settings.mappings.add_comment))
  vim.cmd(format("nnoremap %s :OctoAddReviewSuggestion<CR>", octo.settings.mappings.add_suggestion))
  vim.cmd(format("vnoremap %s :OctoAddReviewSuggestion<CR>", octo.settings.mappings.add_suggestion))

  -- reset quickfix height. Sometimes it messes up after selecting another item
  vim.cmd(format("%dcopen", qf_height))
  vim.cmd [[wincmd p]]
end

function M.next_thread()
  local bufnr = api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  local path = string.match(bufname, "octo://.+/pull/%d+/file/[^/]+/(.+)")
  local current_line = vim.fn.line(".")
  local candidate = math.huge
  if path then
    for _, thread in ipairs(M.threads_for_path(path)) do
      if thread.originalLine > current_line and thread.originalLine < candidate then
        candidate = thread.originalLine
      end
    end
  end
  if candidate < math.huge then
    vim.cmd(":"..candidate)
  end
end

function M.prev_thread()
  local bufnr = api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  local path = string.match(bufname, "octo://.+/pull/%d+/file/[^/]+/(.+)")
  local current_line = vim.fn.line(".")
  local candidate = -1
  if path then
    for _, thread in ipairs(M.threads_for_path(path)) do
      if thread.originalLine < current_line and thread.originalLine > candidate then
        candidate = thread.originalLine
      end
    end
  end
  if candidate > -1 then
    vim.cmd(":"..candidate)
  end
end

function M.next_change()
  local qf = vim.fn.getqflist({idx = 0, size = 0})
  if qf.idx == qf.size then
    vim.cmd [[cfirst]]
  else
    vim.cmd [[cnext]]
  end
  M.select_qf_entry()
end

function M.prev_change()
  local qf = vim.fn.getqflist({idx = 0})
  if qf.idx == 1 then
    vim.cmd [[clast]]
  else
    vim.cmd [[cprev]]
  end
  M.select_qf_entry()
end

--
-- REVIEW PROCESS
--
function M.start_review()
  local repo, number, pr = util.get_repo_number_pr()
  if not repo then return end

  _review_id = -1
  _review_threads = {}
  _review_files = {}

  M.create_review(pr.id, function(resp)
    _review_id = resp.data.addPullRequestReview.pullRequestReview.id
    local threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
    M.update_threads(threads)
    M.initiate_review(repo, number, pr)
  end)
end

function M.create_review(pr_id, callback)
  local query = graphql("start_review_mutation", pr_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          callback(resp)
        end
      end
    }
  )
end

function M.update_threads(threads)
  _review_threads = {}
  for _, thread in ipairs(threads) do
    if thread.startLine == vim.NIL then
      thread.startLine = thread.line
      thread.originalStartLine = thread.originaLine
      thread.startDiffSide = thread.diffSide
    end
    _review_threads[thread.id] = thread
  end
end

function M.threads_for_path(path)
  local threads = {}
  for _, thread in pairs(_review_threads) do
    if path == thread.path then
      table.insert(threads, thread)
    end
  end
  return threads
end

function M.thread_counts(threads)
  local total = #threads
  local resolved = 0
  local outdated = 0
  for _, thread in pairs(threads) do
    if thread.isOutdated then
      outdated = outdated + 1
    end
    if thread.isResolved then
      resolved = resolved + 1
    end
  end
  return total, resolved, outdated
end

function M.update_qf()
  local qf = vim.fn.getqflist({context = 0, idx = 0, items = 0, winid = 0})
  local context = qf.context
  local items = qf.items
  local updated_items = {}
  for _, item in ipairs(items) do
    local path_threads = M.threads_for_path(item.module)
    local total, resolved, outdated = M.thread_counts(path_threads)
    local i = string.find(item.text, "%(")
    local changes = item.text
    if i then
      changes = string.sub(item.text, 1, i - 2)
    end
    item.text = format("%s (%d total %d resolved %d outdated)", changes, total, resolved, outdated)
    table.insert(updated_items, item)
  end
  vim.fn.setqflist({}, "r", {context = context, items = updated_items})
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

          M.update_threads(threads)
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
      args = {"api", "--paginate", url},
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
          M.populate_qf(
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

function M.submit_review()
  if _review_id == -1 then
    api.nvim_err_writeln("No review in progress")
    return
  end

  local winid, bufnr = window.create_centered_float({
    header = "Press <c-a> to approve, <c-m> to comment or <c-r> to request changes"
  })
  api.nvim_set_current_win(winid)
  api.nvim_buf_set_option(bufnr, "syntax", "octo")

  local mapping_opts = {script = true, silent = true, noremap = true}
  api.nvim_buf_set_keymap(
    bufnr,
    "i",
    "<CR>",
    "<CR>",
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "q",
    format(":call nvim_win_close(%d, 1)<CR>", winid),
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<esc>",
    format(":call nvim_win_close(%d, 1)<CR>", winid),
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<C-c>",
    format(":call nvim_win_close(%d, 1)<CR>", winid),
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<C-a>",
    ":lua require'octo.reviews'.do_submit_review('APPROVE')<CR>",
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<C-m>",
    ":lua require'octo.reviews'.do_submit_review('COMMENT')<CR>",
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<C-r>",
    ":lua require'octo.reviews'.do_submit_review('REQUEST_CHANGES')<CR>",
    mapping_opts
  )
  vim.cmd [[normal G]]
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
    api.nvim_err_writeln("[Octo] No review in progress")
    return
  end
  local threads = vim.tbl_values(_review_threads)
  local pending_threads = {}
  for _, thread in ipairs(threads) do
    for _, comment in ipairs(thread.comments.nodes) do
      local review = comment.pullRequestReview
      if review.state == "PENDING" and not util.is_blank(vim.fn.trim(comment.body)) then
        table.insert(pending_threads, thread)
      end
    end
  end
  if #pending_threads == 0 then
    api.nvim_err_writeln("[Octo] No pending comments found")
    return
  else
    require"octo.menu".pending_threads(pending_threads)
  end
end

function M.jump_to_pending_review_thread(thread)
  local qf = vim.fn.getqflist({items = 0})
  local idx
  for i, item in ipairs(qf.items) do
    if thread.path == item.module then
      idx = i
      break
    end
  end
  if idx then
    -- select qf item
    vim.fn.setqflist({}, 'r', {idx = idx })
    M.select_qf_entry({
      diffSide = thread.diffSide,
      startLine = thread.startLine,
      line = thread.line,
    })
  end
end

function M.clear_review_threads()
  local bufnr = api.nvim_get_current_buf()
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if not status or not props then return end
  local diff_bufnr = props.alt_bufnr
  if api.nvim_win_is_valid(props.alt_win) then
    local current_alt_bufnr = api.nvim_win_get_buf(props.alt_win)
    if current_alt_bufnr ~= diff_bufnr then
      api.nvim_win_set_buf(props.alt_win, diff_bufnr)
      local bufname = api.nvim_buf_get_name(current_alt_bufnr)
      if string.match(bufname, "octo://.+/pull/%d+/reviewthreads/.*") then
        api.nvim_buf_delete(current_alt_bufnr, {force = true})
      end
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
  local comment_line = cursor[1]
  local threads_at_cursor = {}
  for _, thread in ipairs(threads) do
    if not thread.isOutdated and
      util.is_thread_placed_in_buffer(thread, bufnr) and
      thread.startLine <= comment_line and thread.line >= comment_line then
      table.insert(threads_at_cursor, thread)
    end
  end

  if #threads_at_cursor == 0 then
    return
  end

  if api.nvim_win_is_valid(props.alt_win) then
    local thread_bufnr = M.create_thread_buffer(props.repo, props.number, props.diffSide, props.path)
    writers.write_threads(thread_bufnr, threads_at_cursor)
    api.nvim_win_set_buf(props.alt_win, thread_bufnr)
    octo.configure_octo_buffer(thread_bufnr)

    -- show comment buffer signs
    signs.render_signcolumn(thread_bufnr)
  else
    api.nvim_err_writeln("[Octo] Cannot find diff window")
  end
end

function M.create_thread_buffer(repo, number, side, path)
  if not vim.startswith(path, "/") then
    path = "/"..path
  end
  local thread_bufname = format("octo://%s/pull/%d/reviewthreads/%s%s", repo, number, side, path)
  local thread_bufnr = vim.fn.bufnr(thread_bufname)
  if thread_bufnr == -1 then
    thread_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(thread_bufnr, thread_bufname)
  else
    api.nvim_buf_set_lines(thread_bufnr, 0, -1, false, {})
    api.nvim_buf_clear_namespace(thread_bufnr, -1, 0, -1)
  end
  api.nvim_buf_set_var(thread_bufnr, "repo", repo)
  api.nvim_buf_set_var(thread_bufnr, "number", number)
  api.nvim_buf_set_var(thread_bufnr, "review_thread_map", {})
  api.nvim_buf_set_option(thread_bufnr, "filetype", "octo")
  api.nvim_buf_set_option(thread_bufnr, "buftype", "acwrite")

  -- add mappings to the thread window buffer
  octo.apply_buffer_mappings(thread_bufnr, "reviewthread")

  api.nvim_buf_set_var(thread_bufnr, "comments", {})

  return thread_bufnr
end

function M.update_thread_signs()
  for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
    local bufnr  = api.nvim_win_get_buf(winid)
    local bufname = api.nvim_buf_get_name(bufnr)
    if string.match(bufname, "octo://.+/pull/%d+/file/.*") then
      M.place_thread_signs(bufnr)
    end
  end
end

function M.place_thread_signs(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
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
      if not thread.isOutdated and util.is_thread_placed_in_buffer(thread, bufnr) then
        for line = thread.startLine, thread.line do
          local sign = "octo_thread"

          if thread.isResolved then
            sign = sign .. "_resolved"
          elseif thread.isOutdated then
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
  if not status or not props then
    return
  end

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
  if not vim.startswith(diff_hunk, "@@") then
    diff_hunk = "@@ "..diff_hunk
  end

  -- create new fake thread
  local thread = {
    originalStartLine = line1,
    originalLine = line2,
    path = props.path,
    isOutdated = false,
    isResolved = false,
    diffSide = props.diffSide,
    isCollapsed = false,
    id = -1,
    comments = {
      nodes = {{
        id = -1,
        author = {login = vim.g.octo_viewer},
        state = "PENDING",
        replyTo = vim.NIL,
        diffHunk = diff_hunk,
        createdAt = vim.fn.strftime("%FT%TZ"),
        body = " ",
        viewerCanUpdate = true,
        viewerCanDelete = true,
        viewerDidAuthor = true,
        pullRequestReview = { id = _review_id },
        reactionGroups = {
          { content = "THUMBS_UP", users = { totalCount = 0 } },
          { content = "THUMBS_DOWN", users = { totalCount = 0 } },
          { content = "LAUGH", users = { totalCount = 0 } },
          { content = "HOORAY", users = { totalCount = 0 } },
          { content = "CONFUSED", users = { totalCount = 0 } },
          { content = "HEART", users = { totalCount = 0 } },
          { content = "ROCKET", users = { totalCount = 0 } },
          { content = "EYES", users = { totalCount = 0 } }
        }
      }}
    }
  }

  local threads = {thread}

  if api.nvim_win_is_valid(props.alt_win) then
    local thread_bufnr = M.create_thread_buffer(props.repo, props.number, props.diffSide, props.path)
    writers.write_threads(thread_bufnr, threads)
    api.nvim_win_set_buf(props.alt_win, thread_bufnr)
    octo.configure_octo_buffer(thread_bufnr)

    if isSuggestion then
      local lines = api.nvim_buf_get_lines(props.content_bufnr, line1-1, line2, false)
      local suggestion = {"```suggestion"}
      vim.list_extend(suggestion, lines)
      table.insert(suggestion, "```")
      api.nvim_buf_set_lines(thread_bufnr, -3, -2, false, suggestion)
      api.nvim_buf_set_option(thread_bufnr, "modified", false)

    end

    -- change to insert mode
    api.nvim_set_current_win(props.alt_win)
    vim.cmd [[normal Gk]]
    vim.cmd [[startinsert]]

    -- show comment buffer signs
    signs.render_signcolumn(thread_bufnr)
  else
    api.nvim_err_writeln("[Octo] Cannot find diff window")
  end

end

return M
