local Layout = require("octo.reviews.layout").Layout
local Rev = require("octo.reviews.rev").Rev
local config = require "octo.config"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local thread_panel = require "octo.reviews.thread-panel"
local window = require "octo.ui.window"
local utils = require "octo.utils"
local ReviewThread = require("octo.reviews.thread").ReviewThread

---@alias ReviewLevel "COMMIT" | "PR"

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

local default_id = -1

---Review constructor.
---@return Review
function Review:new(pull_request)
  local this = {
    pull_request = pull_request,
    id = default_id,
    threads = {},
    files = {},
  }
  setmetatable(this, self)
  return this
end

-- Creates a new review
function Review:create(callback)
  local query = graphql("start_review_mutation", self.pull_request.id)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        callback(resp)
      end
    end,
  }
end

-- Starts a new review
function Review:start()
  self:create(function(resp)
    self.id = resp.data.addPullRequestReview.pullRequestReview.id
    local threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
    self:update_threads(threads)
    self:initiate()
  end)
end

-- Retrieves existing review
function Review:retrieve(callback)
  local query =
    graphql("pending_review_threads_query", self.pull_request.owner, self.pull_request.name, self.pull_request.number)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        callback(resp)
      end
    end,
  }
end

-- Resumes an existing review
function Review:resume()
  self:retrieve(function(resp)
    -- There can only be one pending review for a given user, stop at the first one
    for _, review in ipairs(resp.data.repository.pullRequest.reviews.nodes) do
      if review.viewerDidAuthor then
        self.id = review.id
        break
      end
    end

    if self.id == default_id then
      utils.error "No pending reviews found for viewer"
      return
    end

    local threads = resp.data.repository.pullRequest.reviewThreads.nodes
    self:update_threads(threads)
    self:initiate()
  end)
end

-- Resumes an existing review if there is any, else start one
function Review:start_or_resume()
  self:retrieve(function(resp)
    -- There can only be one pending review for a given user
    for _, review in ipairs(resp.data.repository.pullRequest.reviews.nodes) do
      if review.viewerDidAuthor then
        self.id = review.id
        break
      end
    end

    if self.id == default_id then
      utils.info "No pending review, starting one"
      self:start()
      return
    end

    utils.info "Resuming review"
    local threads = resp.data.repository.pullRequest.reviewThreads.nodes
    self:update_threads(threads)
    self:initiate()
  end)
end

---Register freshly fetched files as this review's files
---Selects and fetches the first unread files
---Defaults to the first file if all files are VIEWED
---@param files FileEntry[]
function Review:set_files_and_select_first(files)
  local selected_file_idx
  for idx, file in ipairs(files) do
    if file.viewed_state ~= "VIEWED" then
      selected_file_idx = idx
      break
    end
  end

  if not selected_file_idx and #files > 0 then
    selected_file_idx = 1
  end

  self.layout.files = files
  if selected_file_idx then
    files[selected_file_idx]:fetch()
    self.layout.selected_file_idx = selected_file_idx
  end
  self.layout:update_files()
end

-- Updates layout to focus on a single commit
function Review:focus_commit(right, left)
  local pr = self.pull_request
  self.layout:close()
  self.layout = Layout:new {
    right = Rev:new(right),
    left = Rev:new(left),
    files = {},
  }
  self.layout:open(self)
  local cb = function(files)
    self:set_files_and_select_first(files)
  end
  if right == self.pull_request.right.commit and left == self.pull_request.left.commit then
    pr:get_changed_files(cb)
  else
    pr:get_commit_changed_files(self.layout.right, cb)
  end
end

---Initiates (starts/resumes) a review
function Review:initiate(opts)
  opts = opts or {}
  local pr = self.pull_request
  local conf = config.values
  if conf.use_local_fs and not utils.in_pr_branch(pr) then
    local choice = vim.fn.confirm("Currently not in PR branch, would you like to checkout?", "&Yes\n&No", 2)
    if choice == 1 then
      utils.checkout_pr_sync { repo = pr.repo, pr_number = pr.number, timeout = conf.timeout }
    end
  end

  -- create the layout
  self.layout = Layout:new {
    left = opts.left or pr.left,
    right = opts.right or pr.right,
    files = {},
  }
  self.layout:open(self)

  pr:get_changed_files(function(files)
    self:set_files_and_select_first(files)
  end)
end

function Review:discard()
  local query =
    graphql("pending_review_threads_query", self.pull_request.owner, self.pull_request.name, self.pull_request.number)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        if #resp.data.repository.pullRequest.reviews.nodes == 0 then
          utils.error "No pending reviews found"
          return
        end
        self.id = resp.data.repository.pullRequest.reviews.nodes[1].id

        local choice = vim.fn.confirm("All pending comments will get deleted, are you sure?", "&Yes\n&No\n&Cancel", 2)
        if choice == 1 then
          local delete_query = graphql("delete_pull_request_review_mutation", self.id)
          gh.run {
            args = { "api", "graphql", "-f", string.format("query=%s", delete_query) },
            cb = function(output_inner, stderr_inner)
              if stderr_inner and not utils.is_blank(stderr_inner) then
                utils.error(stderr_inner)
              elseif output_inner then
                self.id = default_id
                self.threads = {}
                self.files = {}
                utils.info "Pending review discarded"
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
    if not thread.isOutdated then
      self.threads[thread.id] = thread
    end
  end
  if self.layout then
    self.layout.file_panel:render()
    self.layout.file_panel:redraw()
    local file = self.layout:get_current_file()
    if file then
      file:place_signs()
    end
  end
end

function Review:collect_submit_info()
  if self.id == default_id then
    utils.error "No review in progress"
    return
  end

  local conf = config.values
  local winid, bufnr = window.create_centered_float {
    header = string.format(
      "Press %s to approve, %s to comment or %s to request changes",
      conf.mappings.submit_win.approve_review.lhs,
      conf.mappings.submit_win.comment_review.lhs,
      conf.mappings.submit_win.request_changes.lhs
    ),
  }
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_buf_set_option(bufnr, "syntax", "octo")
  utils.apply_mappings("submit_win", bufnr)
  vim.cmd [[normal G]]
end

function Review:submit(event)
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, default_id, false)
  local body = utils.escape_char(utils.trim(table.concat(lines, "\n")))
  local query = graphql("submit_pull_request_review_mutation", self.id, event, body, { escape = false })
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        utils.info "Review was submitted successfully!"
        pcall(vim.api.nvim_win_close, winid, 0)
        self.layout:close()
      end
    end,
  }
end

function Review:show_pending_comments()
  local pending_threads = {}
  for _, thread in ipairs(vim.tbl_values(self.threads)) do
    for _, comment in ipairs(thread.comments.nodes) do
      if comment.pullRequestReview.state == "PENDING" and not utils.is_blank(utils.trim(comment.body)) then
        table.insert(pending_threads, thread)
      end
    end
  end
  if #pending_threads == 0 then
    utils.error "No pending comments found"
    return
  else
    require("octo.picker").pending_threads(pending_threads)
  end
end

function Review:add_comment(isSuggestion)
  -- check if we are on the diff layout and return early if not
  local bufnr = vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  if not split or not path then
    return
  end

  local file = self.layout:get_current_file()
  if not file then
    return
  end

  -- get visual selected line range, used if coming from a keymap where current
  -- mode can be evaluated.
  local line1, line2 = utils.get_lines_from_context "visual"
  -- if we came from the command line the command options will provide line
  -- range
  if OctoLastCmdOpts ~= nil then
    line1 = OctoLastCmdOpts.line1
    line2 = OctoLastCmdOpts.line2
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
      utils.error "Cannot place comments outside diff hunks"
      return
    end
    if not vim.startswith(diff_hunk, "@@") then
      diff_hunk = "@@ " .. diff_hunk
    end
  else
    -- not printing diff hunk for added files
    -- we will get the right diff hunk from the server when updating the threads
    -- TODO: trigger a thread update?
  end

  self.layout:ensure_layout()

  local alt_win = file:get_alternative_win(split)
  if vim.api.nvim_win_is_valid(alt_win) then
    local pr = file.pull_request

    -- create a thread stub representing the new comment

    local commit, commit_abbrev
    if split == "LEFT" then
      commit = self.layout.left.commit
      commit_abbrev = self.layout.left:abbrev()
    elseif split == "RIGHT" then
      commit = self.layout.right.commit
      commit_abbrev = self.layout.right:abbrev()
    end
    local threads = {
      ReviewThread:stub {
        line1 = line1,
        line2 = line2,
        file_path = file.path,
        split = split,
        diff_hunk = diff_hunk,
        commit = commit,
        commit_abbrev = commit_abbrev,
        review_id = self.id,
      },
    }

    -- Make sure review thread panel is visible if not already
    -- The thread panel could be hidden if user has `reviews.auto_show_threads` set to false in their config
    -- or, less likely, if the add comment command is invoked before the autocmd has concluded,
    thread_panel.show_review_threads(false)
    local thread_buffer = thread_panel.create_thread_buffer(threads, pr.repo, pr.number, split, file.path)
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
      vim.cmd [[diffoff!]]
      vim.cmd [[normal! vvGk]]
      vim.cmd [[startinsert]]

      vim.keymap.set("n", "q", function()
        thread_panel.hide_thread_buffer(split, file)
        local file_win = file:get_win(split)
        if vim.api.nvim_win_is_valid(file_win) then
          vim.api.nvim_set_current_win(file_win)
        end
      end, { buffer = thread_buffer.bufnr })
    end
  else
    utils.error("Cannot find diff window " .. alt_win)
  end
end

---Get the review level, aka whether the review is at commit or PR level
---@return ReviewLevel
function Review:get_level()
  if
    self.layout.left.commit == self.pull_request.left.commit
    and self.layout.right.commit == self.pull_request.right.commit
  then
    return "PR"
  end
  return "COMMIT"
end

local M = {}

M.reviews = {}

M.Review = Review

function M.add_review_comment(isSuggestion)
  local review = M.get_current_review()
  if not review then
    error "Could not find review"
  end
  review:add_comment(isSuggestion)
end

function M.jump_to_pending_review_thread(thread)
  local current_review = M.get_current_review()
  if not current_review then
    return
  end
  for _, file in ipairs(current_review.layout.files) do
    if thread.path == file.path then
      current_review.layout:ensure_layout()
      current_review.layout:set_current_file(file)
      local win = file:get_win(thread.diffSide)
      if vim.api.nvim_win_is_valid(win) then
        local review_level = current_review:get_level()
        -- jumping to the original position in case we are reviewing any commit
        -- jumping to the PR position if we are reviewing the last commit
        -- This may result in a jump to the wrong line when the review is neither in the last commit or the original one
        local line = review_level == "COMMIT" and thread.originalStartLine or thread.startLine
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_cursor(win, { line, 0 })
      else
        utils.error "Cannot find diff window"
      end
      break
    end
  end
end

--- Get the current review according to the tab page
--- @return Review | nil
function M.get_current_review()
  local current_tabpage = vim.api.nvim_get_current_tabpage()
  return M.reviews[tostring(current_tabpage)]
end

--- Get the diff Layout of the review if any
--- @return Layout | nil
function M.get_current_layout()
  local current_review = M.get_current_review()
  if current_review then
    return M.get_current_review().layout
  end
end

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

--- Get the pull request associated with current buffer.
--- Fall back to pull request associated with the current branch if not in an Octo buffer.
--- @param cb function
local function get_pr_from_buffer_or_current_branch(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]

  if not buffer then
    -- We are not in an octo buffer, try and fallback to the current branch's pr
    utils.get_pull_request_for_current_branch(cb)
    return
  end

  local pull_request = buffer:get_pr()
  if pull_request then
    cb(pull_request)
  else
    pull_request = utils.get_pull_request_for_current_branch(cb)
  end
end

function M.start_review()
  get_pr_from_buffer_or_current_branch(function(pull_request)
    local current_review = Review:new(pull_request)
    current_review:start()
  end)
end

function M.resume_review()
  get_pr_from_buffer_or_current_branch(function(pull_request)
    local current_review = Review:new(pull_request)
    current_review:resume()
  end)
end

function M.start_or_resume_review()
  get_pr_from_buffer_or_current_branch(function(pull_request)
    local current_review = Review:new(pull_request)
    current_review:start_or_resume()
  end)
end

function M.discard_review()
  local current_review = M.get_current_review()
  if current_review then
    current_review:discard()
  else
    utils.error "Please start or resume a review first"
  end
end

function M.submit_review()
  local current_review = M.get_current_review()
  if current_review then
    current_review:collect_submit_info()
  else
    utils.error "Please start or resume a review first"
  end
end

return M
