local FileEntry = require("octo.reviews.file-entry").FileEntry
local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local Layout = require("octo.reviews.layout").Layout
local utils = require "octo.utils"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local window = require "octo.window"
local config = require "octo.config"
local mappings = require "octo.mappings"

local status_map = {
  modified = "M",
  added = "A",
  deleted = "D",
  renamed = "R",
}

local M = {}

M.reviews = {}

function M.on_tab_leave()
  local current_review = M.get_current_review()
  if current_review and current_review.layout then
    current_review.layout:on_leave()
  end
end

function M.on_win_leave()
  local current_review = M.get_current_review()
  if current_review and current_review.layout then
    current_review.layout:on_win_leave()
  end
end

function M.close(tabpage)
  if tabpage then
    local review = M.reviews[tostring(tabpage)]
    if review and review.layout then
      review.layout:close()
    end
    M.reviews[tostring(tabpage)] = nil
  end
end

---@class Review
---@field repo string
---@field number integer
---@field id integer
---@field threads table[]
---@field files FileEntry[]
---@field layout Layout
---@field pull_request PullRequest
local Review = {}
Review.__index = Review

---Review constructor.
---@return Review
function Review:new(pull_request)
  local this = {
    pull_request = pull_request,
    id = -1,
    threads = {},
    files = {},
  }
  setmetatable(this, self)
  return this
end

function Review:create(callback)
  local query = graphql("start_review_mutation", self.pull_request.id)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        callback(resp)
      end
    end,
  }
end

function Review:start()
  self:create(function(resp)
    self.id = resp.data.addPullRequestReview.pullRequestReview.id
    local threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
    self:update_threads(threads)
    self:initiate()
  end)
end

function Review:resume()
  local query = graphql(
    "pending_review_threads_query",
    self.pull_request.owner,
    self.pull_request.name,
    self.pull_request.number
  )
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        if #resp.data.repository.pullRequest.reviews.nodes == 0 then
          utils.notify("No pending reviews found", 2)
          return
        end

        -- There can only be one pending review for a given user
        for _, review in ipairs(resp.data.repository.pullRequest.reviews.nodes) do
          if review.viewerDidAuthor then
            self.id = review.id
            break
          end
        end

        if not self.id then
          vim.notify("[Octo] No pending reviews found for viewer", 2)
          return
        end

        local threads = resp.data.repository.pullRequest.reviewThreads.nodes
        self:update_threads(threads)
        self:initiate()
      end
    end,
  }
end

function Review:initiate()
  local pr = self.pull_request

  -- create the layout
  self.layout = Layout:new {
    left = pr.left,
    right = pr.right,
    files = {},
  }
  self.layout:open(self)

  -- fetch the changed files
  local url = string.format("repos/%s/pulls/%d/files", pr.repo, pr.number)
  gh.run {
    args = { "api", "--paginate", url, "--jq", "." },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local results = utils.get_flatten_pages(output)
        local files = {}
        for i, result in ipairs(results) do
          local entry = FileEntry:new {
            path = result.filename,
            previous_path = result.previous_filename,
            patch = result.patch,
            pull_request = pr,
            status = status_map[result.status],
            stats = {
              additions = result.additions,
              deletions = result.deletions,
              changes = result.changes,
            },
          }
          table.insert(files, entry)
          -- pre-fetch the first file
          if i == 1 then
            entry:fetch()
          end
        end
        self.layout.files = files

        -- update the file list
        self.layout:update_files()
      end
    end,
  }
end

function Review:discard()
  local query = graphql(
    "pending_review_threads_query",
    self.pull_request.owner,
    self.pull_request.name,
    self.pull_request.number
  )
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        if #resp.data.repository.pullRequest.reviews.nodes == 0 then
          utils.notify("No pending reviews found", 2)
          return
        end
        self.id = resp.data.repository.pullRequest.reviews.nodes[1].id

        local choice = vim.fn.confirm("All pending comments will get deleted, are you sure?", "&Yes\n&No\n&Cancel", 2)
        if choice == 1 then
          local delete_query = graphql("delete_pull_request_review_mutation", self.id)
          gh.run {
            args = { "api", "graphql", "-f", string.format("query=%s", delete_query) },
            cb = function(output, stderr)
              if stderr and not utils.is_blank(stderr) then
                vim.notify(stderr, 2)
              elseif output then
                self.id = -1
                self.threads = {}
                self.files = {}
                utils.notify("Pending review discarded", 1)
                vim.cmd [[tabclose]]
              end
            end,
          }
        end
      end
    end,
  }
end

function Review:update_threads(threads)
  self.threads = {}
  for _, thread in ipairs(threads) do
    if thread.line == vim.NIL then
      thread.line = thread.originalLine
    end
    if thread.startLine == vim.NIL then
      thread.startLine = thread.line
      thread.startDiffSide = thread.diffSide
      thread.originalStartLine = thread.originalLine
    end
    self.threads[thread.id] = thread
  end
  if self.layout then
    self.layout.file_panel:render()
    self.layout.file_panel:redraw()
    if self.layout:cur_file() then
      self.layout:cur_file():place_signs()
    end
  end
end

function Review:collect_submit_info()
  if self.id == -1 then
    utils.notify("No review in progress", 2)
    return
  end

  local conf = config.get_config()
  local winid, bufnr = window.create_centered_float {
    header = string.format(
      "Press %s to approve, %s to comment or %s to request changes",
      conf.mappings.submit_win.approve_review,
      conf.mappings.submit_win.comment_review,
      conf.mappings.submit_win.request_changes
    ),
  }
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_buf_set_option(bufnr, "syntax", "octo")
  for rhs, lhs in pairs(conf.mappings.submit_win) do
    vim.api.nvim_buf_set_keymap(bufnr, "n", lhs, mappings.callback(rhs), { noremap = true, silent = true })
  end
  vim.cmd [[normal G]]
end

function Review:submit(event)
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body = utils.escape_chars(vim.fn.trim(table.concat(lines, "\n")))
  local query = graphql("submit_pull_request_review_mutation", self.id, event, body, { escape = false })
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        utils.notify("Review was submitted successfully!", 1)
        pcall(vim.api.nvim_win_close, winid, 0)
        self.layout:close()
      end
    end,
  }
end

M.Review = Review

function M.start_review()
  local pull_request = utils.get_current_pr()
  if pull_request then
    local current_review = Review:new(pull_request)
    current_review:start()
  else
    pull_request = utils.get_pull_request_for_current_branch(function(pull_request)
      local current_review = Review:new(pull_request)
      current_review:start()
    end)
  end
end

function M.resume_review()
  local pull_request = utils.get_current_pr()
  if pull_request then
    local current_review = Review:new(pull_request)
    current_review:resume()
  else
    pull_request = utils.get_pull_request_for_current_branch(function(pull_request)
      local current_review = Review:new(pull_request)
      current_review:resume()
    end)
  end
end

function M.discard_review()
  local current_review = M.get_current_review()
  if current_review then
    current_review:discard()
  end
end

------------
--- THREADS
------------

function M.hide_review_threads()
  -- This function is called from a very broad CursorMoved
  -- Check if we are in a diff buffer and otherwise return early
  local bufnr = vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  if not split or not path then
    return
  end

  local review = M.get_current_review()
  local file = review.layout:cur_file()
  if not file then
    return
  end

  local alt_buf = file:get_alternative_buf(split)
  local alt_win = file:get_alternative_win(split)
  if vim.api.nvim_win_is_valid(alt_win) and vim.api.nvim_buf_is_valid(alt_buf) then
    local current_alt_bufnr = vim.api.nvim_win_get_buf(alt_win)
    if current_alt_bufnr ~= alt_buf then
      -- if we are not showing the corresponging alternative diff buffer, do so
      vim.api.nvim_win_set_buf(alt_win, alt_buf)
      -- Scroll to trigger the scrollbind and sync the windows. This works more
      -- consistently than calling `:syncbind`.
      vim.cmd [[exec "normal! \<c-y>"]]
    end
  end
end

function M.show_review_threads()
  -- This function is called from a very broad CursorHold
  -- Check if we are in a diff buffer and otherwise return early
  local bufnr = vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  if not split or not path then
    return
  end

  local review = M.get_current_review()
  local file = review.layout:cur_file()
  if not file then
    return
  end

  local pr = file.pull_request
  local threads = vim.tbl_values(review.threads)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local threads_at_cursor = {}
  for _, thread in ipairs(threads) do
    --if utils.is_thread_placed_in_buffer(thread, bufnr) and thread.startLine <= line and thread.line >= line then
    if utils.is_thread_placed_in_buffer(thread, bufnr) and thread.startLine == line then
      table.insert(threads_at_cursor, thread)
    end
  end

  if #threads_at_cursor == 0 then
    return
  end

  review.layout:ensure_layout()
  local alt_win = file:get_alternative_win(split)
  if vim.api.nvim_win_is_valid(alt_win) then
    local thread_buffer = M._create_thread_buffer(threads_at_cursor, pr.repo, pr.number, split, file.path, line)
    if thread_buffer then
      table.insert(file.associated_bufs, thread_buffer.bufnr)
      vim.api.nvim_win_set_buf(alt_win, thread_buffer.bufnr)
      thread_buffer:configure()
      vim.api.nvim_buf_call(thread_buffer.bufnr, function()
        -- TODO: remove first line but only if its empty and if it has no virtualtext
        --vim.cmd [[normal ggdd]]
        pcall(vim.cmd, "normal ]c")
      end)
    end
  end
end

function M._create_thread_buffer(threads, repo, number, side, path, line)
  local current_review = M.get_current_review()
  if not vim.startswith(path, "/") then
    path = "/" .. path
  end
  local bufname = string.format("octo://%s/review/%s/threads/%s%s:%d", repo, current_review.id, side, path, line)
  local bufnr = vim.fn.bufnr(bufname)
  local buffer
  if bufnr == -1 then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, bufname)
    buffer = OctoBuffer:new {
      bufnr = bufnr,
      number = number,
      repo = repo,
    }
    buffer:render_threads(threads)
    buffer:render_signcolumn()
  elseif vim.api.nvim_buf_is_loaded(bufnr) then
    buffer = octo_buffers[bufnr]
  else
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  return buffer
end

function M.add_review_comment(isSuggestion)
  local bufnr = vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  if not split or not path then
    return
  end

  local review = M.get_current_review()
  local file = review.layout:cur_file()
  if not file then
    return
  end

  -- get visual selected line range
  local line1, line2
  if vim.fn.getpos("'<")[2] == vim.fn.getcurpos()[2] then
    line1 = vim.fn.getpos("'<")[2]
    line2 = vim.fn.getpos("'>")[2]
  else
    line1 = vim.fn.getcurpos()[2]
    line2 = vim.fn.getcurpos()[2]
  end
  local comment_ranges, current_bufnr
  if split == "RIGHT" then
    comment_ranges = file.right_comment_ranges
    current_bufnr = file.right_bufid
  elseif split == "LEFT" then
    comment_ranges = file.left_comment_ranges
    current_bufnr = file.left_bufid
  else
    return
  end

  local diff_hunk
  -- for non-added files, check we are in a valid comment range
  if file.status ~= "A" then
    for i, range in ipairs(comment_ranges) do
      if range[1] <= line1 and range[2] >= line2 then
        diff_hunk = file.diffhunks[i]
        break
      end
    end
    if not diff_hunk then
      utils.notify("Cannot place comments outside diff hunks", 2)
      return
    end
    if not vim.startswith(diff_hunk, "@@") then
      diff_hunk = "@@ " .. diff_hunk
    end
  end

  review.layout:ensure_layout()

  local alt_win = file:get_alternative_win(split)
  if vim.api.nvim_win_is_valid(alt_win) then
    local pr = file.pull_request
    local threads = {
      {
        originalStartLine = line1,
        originalLine = line2,
        path = file.path,
        isOutdated = false,
        isResolved = false,
        diffSide = split,
        isCollapsed = false,
        id = -1,
        comments = {
          nodes = {
            {
              id = -1,
              author = { login = vim.g.octo_viewer },
              state = "PENDING",
              replyTo = vim.NIL,
              diffHunk = diff_hunk,
              createdAt = vim.fn.strftime "%FT%TZ",
              body = " ",
              viewerCanUpdate = true,
              viewerCanDelete = true,
              viewerDidAuthor = true,
              pullRequestReview = { id = review.id },
              reactionGroups = {
                { content = "THUMBS_UP", users = { totalCount = 0 } },
                { content = "THUMBS_DOWN", users = { totalCount = 0 } },
                { content = "LAUGH", users = { totalCount = 0 } },
                { content = "HOORAY", users = { totalCount = 0 } },
                { content = "CONFUSED", users = { totalCount = 0 } },
                { content = "HEART", users = { totalCount = 0 } },
                { content = "ROCKET", users = { totalCount = 0 } },
                { content = "EYES", users = { totalCount = 0 } },
              },
            },
          },
        },
      },
    }
    -- TODO: if there are threads for that line, there should be a buffer already showing them
    -- or maybe not if the user is very quick
    local thread_buffer = M._create_thread_buffer(threads, pr.repo, pr.number, split, file.path, line1)
    if thread_buffer then
      table.insert(file.associated_bufs, thread_buffer.bufnr)
      vim.api.nvim_win_set_buf(alt_win, thread_buffer.bufnr)
      vim.api.nvim_set_current_win(alt_win)
      if isSuggestion then
        local lines = vim.api.nvim_buf_get_lines(current_bufnr, line1 - 1, line2, false)
        local suggestion = { "```suggestion" }
        vim.list_extend(suggestion, lines)
        table.insert(suggestion, "```")
        vim.api.nvim_buf_set_lines(thread_buffer.bufnr, -3, -2, false, suggestion)
        vim.api.nvim_buf_set_option(thread_buffer.bufnr, "modified", false)
      end
      thread_buffer:configure()
      -- TODO: remove first line but only if its empty and if it has no virtualtext
      --vim.cmd [[normal ggdd]]
      vim.cmd [[normal Gk]]
      vim.cmd [[startinsert]]
    end
  else
    utils.notify("Cannot find diff window", 2)
  end
end

function M.get_current_review()
  local current_tabpage = vim.api.nvim_get_current_tabpage()
  return M.reviews[tostring(current_tabpage)]
end

function M.show_pending_comments()
  local current_review = M.get_current_review()
  if not current_review then
    utils.notify("No review in progress", 2)
    return
  end
  local pending_threads = {}
  for _, thread in ipairs(vim.tbl_values(current_review.threads)) do
    for _, comment in ipairs(thread.comments.nodes) do
      if comment.pullRequestReview.state == "PENDING" and not utils.is_blank(vim.fn.trim(comment.body)) then
        table.insert(pending_threads, thread)
      end
    end
  end
  if #pending_threads == 0 then
    utils.notify("No pending comments found", 2)
    return
  else
    require("octo.picker").pending_threads(pending_threads)
  end
end

function M.jump_to_pending_review_thread(thread)
  local current_review = M.get_current_review()
  for _, file in ipairs(current_review.layout.files) do
    if thread.path == file.path then
      current_review.layout:set_file(file)
      local win = file:get_win(thread.diffSide)
      vim.api.nvim_win_set_cursor(win, { thread.startLine, 0 })
      break
    end
  end
end

return M
