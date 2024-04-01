local Layout = require("octo.reviews.layout").Layout
local Rev = require("octo.reviews.rev").Rev
local config = require "octo.config"
local backend = require "octo.backend"
local thread_panel = require "octo.reviews.thread-panel"
local window = require "octo.ui.window"
local utils = require "octo.utils"

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

-- Creates a new review
function Review:create(callback)
  local func = backend.get_funcs()["review_start_review_mutation"]
  func(self.pull_request.id, callback)
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
  local func = backend.get_funcs()["review_retrieve"]
  func(self.pull_request, callback)
end

-- Resumes an existing review
function Review:resume()
  self:retrieve(function(resp)
    if #resp.data.repository.pullRequest.reviews.nodes == 0 then
      utils.error "No pending reviews found"
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
      vim.error "No pending reviews found for viewer"
      return
    end

    local threads = resp.data.repository.pullRequest.reviewThreads.nodes
    self:update_threads(threads)
    self:initiate()
  end)
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
    -- pre-fetch the first file
    if #files > 0 then
      files[1]:fetch()
    end
    self.layout.files = files
    self.layout:update_files()
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
  if conf.use_local_fs and not utils.in_pr_branch(pr.bufnr) then
    local choice = vim.fn.confirm("Currently not in PR branch, would you like to checkout?", "&Yes\n&No", 2)
    if choice == 1 then
      utils.checkout_pr_sync(pr.number)
    end
  end

  -- create the layout
  self.layout = Layout:new {
    -- TODO: rename to left_rev and right_rev
    left = opts.left or pr.left,
    right = opts.right or pr.right,
    files = {},
  }
  self.layout:open(self)

  pr:get_changed_files(function(files)
    -- pre-fetch the first file
    if #files > 0 then
      files[1]:fetch()
    end
    self.layout.files = files
    self.layout:update_files()
  end)
end

function Review:discard()
  local func = backend.get_funcs()["review_discard"]
  func(self)
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
  local func = backend.get_funcs()["review_submit"]
  func(self.id, self.layout, event)
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

  local file = self.layout:cur_file()
  if not file then
    return
  end

  -- get visual selected line range
  local line1, line2 = utils.get_lines_from_context "visual"

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
              url = vim.NIL,
              diffHunk = diff_hunk,
              createdAt = vim.fn.strftime "%FT%TZ",
              originalCommit = { oid = commit, abbreviatedOid = commit_abbrev },
              body = " ",
              viewerCanUpdate = true,
              viewerCanDelete = true,
              viewerDidAuthor = true,
              pullRequestReview = { id = self.id },
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
    end
  else
    utils.error("Cannot find diff window " .. alt_win)
  end
end

function Review:get_level()
  local review_level = "COMMIT"
  if
    self.layout.left.commit == self.pull_request.left.commit
    and self.layout.right.commit == self.pull_request.right.commit
  then
    review_level = "PR"
  end
  return review_level
end

local M = {}

M.reviews = {}

M.Review = Review

function M.add_review_comment(isSuggestion)
  local review = M.get_current_review()
  review:add_comment(isSuggestion)
end

function M.jump_to_pending_review_thread(thread)
  local current_review = M.get_current_review()
  for _, file in ipairs(current_review.layout.files) do
    if thread.path == file.path then
      current_review.layout:ensure_layout()
      current_review.layout:set_file(file)
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

function M.get_current_review()
  local current_tabpage = vim.api.nvim_get_current_tabpage()
  return M.reviews[tostring(current_tabpage)]
end

function M.get_current_layout()
  local current_review = M.get_current_review()
  if current_review then
    return current_review.layout
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

function M.start_review()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    utils.error "No Octo buffer found"
    return
  end
  local pull_request = buffer:get_pr()
  if pull_request then
    local current_review = Review:new(pull_request)
    current_review:start()
  else
    pull_request = utils.get_pull_request_for_current_branch(function(pr)
      local current_review = Review:new(pr)
      current_review:start()
    end)
  end
end

function M.resume_review()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    utils.error "No Octo buffer found"
    return
  end
  local pull_request = buffer:get_pr()
  if pull_request then
    local current_review = Review:new(pull_request)
    current_review:resume()
  else
    pull_request = utils.get_pull_request_for_current_branch(function(pr)
      local current_review = Review:new(pr)
      current_review:resume()
    end)
  end
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
