local BodyMetadata = require("octo.model.body-metadata").BodyMetadata
local TitleMetadata = require("octo.model.title-metadata").TitleMetadata
local utils = require "octo.utils"
local mappings = require "octo.mappings"
local constants = require "octo.constants"
local config = require "octo.config"
local writers = require "octo.writers"
local folds = require "octo.folds"
local signs = require "octo.signs"
local graphql = require "octo.graphql"
local gh = require "octo.gh"

local M = {}

---@class OctoBuffer
---@field bufnr integer
---@field number integer
---@field repo string
---@field kind string
---@field titleMetadata TitleMetadata
---@field bodyMetadata BodyMetadata
---@field commentsMetadata CommentMetadata[]
---@field threadsMetadata ThreadMetadata[]
---@field node table
---@field taggable_users string[]
local OctoBuffer = {}
OctoBuffer.__index = OctoBuffer

---OctoBuffer constructor.
---@return OctoBuffer
function OctoBuffer:new(opts)
  local this = {
    bufnr = opts.bufnr or vim.api.nvim_get_current_buf(),
    number = opts.number,
    repo = opts.repo,
    node = opts.node,
    titleMetadata = TitleMetadata:new(),
    bodyMetadata = BodyMetadata:new(),
    commentsMetadata = opts.commentsMetadata or {},
    threadsMetadata = opts.threadsMetadata or {},
  }
  if this.repo then
    this.owner, this.name = utils.split_repo(this.repo)
  end
  if this.node and this.node.commits then
    this.kind = "pull"
    this.taggable_users = { this.node.author.login }
  elseif this.node and this.number then
    this.kind = "issue"
    this.taggable_users = { this.node.author.login }
  elseif this.node and not this.number then
    this.kind = "repo"
  else
    this.kind = "reviewthread"
  end
  setmetatable(this, self)
  octo_buffers[this.bufnr] = this
  return this
end

M.OctoBuffer = OctoBuffer

function OctoBuffer:apply_mappings()
  local mapping_opts = { silent = true, noremap = true }
  local conf = config.get_config()

  local kind = self.kind
  if self.kind == "pull" then
    kind = "pull_request"
  elseif self.kind == "reviewthread" then
    kind = "review_thread"
  end

  for rhs, lhs in pairs(conf.mappings[kind]) do
    vim.api.nvim_buf_set_keymap(self.bufnr, "n", lhs, mappings.callback(rhs), mapping_opts)
  end

  -- autocomplete
  vim.api.nvim_buf_set_keymap(self.bufnr, "i", "@", "@<C-x><C-o>", mapping_opts)
  vim.api.nvim_buf_set_keymap(self.bufnr, "i", "#", "#<C-x><C-o>", mapping_opts)
end

function OctoBuffer:clear()
  -- clear buffer
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})

  -- delete extmarks
  local extmarks = vim.api.nvim_buf_get_extmarks(self.bufnr, constants.OCTO_COMMENT_NS, 0, -1, {})
  for _, m in ipairs(extmarks) do
    vim.api.nvim_buf_del_extmark(self.bufnr, constants.OCTO_COMMENT_NS, m[1])
  end
end

function OctoBuffer:render_repo()
  self:clear()
  writers.write_repo(self.bufnr, self.node)

  -- reset modified option
  vim.api.nvim_buf_set_option(self.bufnr, "modified", false)

  self.ready = true
end

function OctoBuffer:render_issue()
  self:clear()

  -- write title
  writers.write_title(self.bufnr, self.node.title, 1)

  -- write details in buffer
  writers.write_details(self.bufnr, self.node)

  -- write issue/pr status
  writers.write_state(self.bufnr, self.node.state:upper(), self.number)

  -- write body
  writers.write_body(self.bufnr, self.node)

  -- write body reactions
  local reaction_line
  if utils.count_reactions(self.node.reactionGroups) > 0 then
    local line = vim.api.nvim_buf_line_count(self.bufnr) + 1
    writers.write_block(self.bufnr, { "", "" }, line)
    reaction_line = writers.write_reactions(self.bufnr, self.node.reactionGroups, line)
  end
  self.bodyMetadata.reactionGroups = self.node.reactionGroups
  self.bodyMetadata.reactionLine = reaction_line

  -- write timeline items
  local unrendered_labeled_events = {}
  local unrendered_unlabeled_events = {}
  local prev_is_event = false
  for _, item in ipairs(self.node.timelineItems.nodes) do
    if item.__typename ~= "LabeledEvent" and #unrendered_labeled_events > 0 then
      writers.write_labeled_events(self.bufnr, unrendered_labeled_events, "added", prev_is_event)
      unrendered_labeled_events = {}
      prev_is_event = true
    end
    if item.__typename ~= "UnlabeledEvent" and #unrendered_unlabeled_events > 0 then
      writers.write_labeled_events(self.bufnr, unrendered_unlabeled_events, "removed", prev_is_event)
      unrendered_unlabeled_events = {}
      prev_is_event = true
    end

    if item.__typename == "IssueComment" then
      if prev_is_event then
        writers.write_block(self.bufnr, { "" })
      end

      -- write the comment
      local start_line, end_line = writers.write_comment(self.bufnr, item, "IssueComment")
      folds.create(self.bufnr, start_line + 1, end_line, true)
      prev_is_event = false
    elseif item.__typename == "PullRequestReview" then
      if prev_is_event then
        writers.write_block(self.bufnr, { "" })
      end

      -- A review can have 0+ threads
      local threads = {}
      for _, comment in ipairs(item.comments.nodes) do
        for _, reviewThread in ipairs(self.node.reviewThreads.nodes) do
          if comment.id == reviewThread.comments.nodes[1].id then
            -- found a thread for the current review
            table.insert(threads, reviewThread)
          end
        end
      end

      -- skip reviews with no threads and empty body
      if #threads > 0 or not utils.is_blank(item.body) then
        -- print review header and top level comment
        local review_start, review_end = writers.write_comment(self.bufnr, item, "PullRequestReview")

        -- print threads
        if #threads > 0 then
          review_end = writers.write_threads(self.bufnr, threads, review_start, review_end)
          folds.create(self.bufnr, review_start + 1, review_end, true)
        end
        writers.write_block(self.bufnr, { "" })
        prev_is_event = false
      end
    elseif item.__typename == "AssignedEvent" then
      writers.write_assigned_event(self.bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "PullRequestCommit" then
      writers.write_commit_event(self.bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "MergedEvent" then
      writers.write_merged_event(self.bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "ClosedEvent" then
      writers.write_closed_event(self.bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "ReopenedEvent" then
      writers.write_reopened_event(self.bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "LabeledEvent" then
      table.insert(unrendered_labeled_events, item)
    elseif item.__typename == "UnlabeledEvent" then
      table.insert(unrendered_unlabeled_events, item)
    elseif item.__typename == "ReviewRequestedEvent" then
      writers.write_review_requested_event(self.bufnr, item, "removed", prev_is_event)
      prev_is_event = true
    elseif item.__typename == "ReviewRequestRemovedEvent" then
      writers.write_review_request_removed_event(self.bufnr, item, "removed", prev_is_event)
      prev_is_event = true
    elseif item.__typename == "ReviewDismissedEvent" then
      writers.write_review_dismissed_event(self.bufnr, item, "removed", prev_is_event)
      prev_is_event = true
    end
  end
  if prev_is_event then
    writers.write_block(self.bufnr, { "" })
  end

  -- drop undo history
  utils.clear_history()

  -- reset modified option
  vim.api.nvim_buf_set_option(self.bufnr, "modified", false)

  self.ready = true
end

function OctoBuffer:render_threads(threads)
  self:clear()
  writers.write_threads(self.bufnr, threads)
  self.ready = true
end

function OctoBuffer:configure()
  -- configure buffer
  vim.api.nvim_buf_call(self.bufnr, function()
    --options
    vim.cmd [[setlocal filetype=octo]]
    vim.cmd [[setlocal buftype=acwrite]]
    vim.cmd [[setlocal omnifunc=v:lua.octo_omnifunc]]
    vim.cmd [[setlocal conceallevel=2]]
    vim.cmd [[setlocal signcolumn=yes]]
    vim.cmd [[setlocal foldenable]]
    vim.cmd [[setlocal foldtext=v:lua.octo_foldtext()]]
    vim.cmd [[setlocal foldmethod=manual]]
    vim.cmd [[setlocal foldcolumn=3]]
    vim.cmd [[setlocal foldlevelstart=99]]
    vim.cmd [[setlocal nonumber norelativenumber nocursorline wrap]]
    vim.cmd [[setlocal fillchars=fold:⠀,foldopen:⠀,foldclose:⠀,foldsep:⠀]]

    -- autocmds
    vim.cmd [[ augroup octo_buffer_autocmds ]]
    vim.cmd(string.format([[ au! * <buffer=%d> ]], self.bufnr))
    vim.cmd(string.format([[ au TextChanged <buffer=%d> lua require"octo".render_signcolumn() ]], self.bufnr))
    vim.cmd(string.format([[ au TextChangedI <buffer=%d> lua require"octo".render_signcolumn() ]], self.bufnr))
    vim.cmd [[ augroup END ]]
  end)

  self:apply_mappings()
end

-- This function accumulates all the taggable users into a single list that
-- gets set as a buffer variable `taggable_users`. If this list of users
-- is needed syncronously, this function will need to be refactored.
-- The list of taggable users should contain:
--   - The PR author
--   - The authors of all the existing comments
--   - The contributors of the repo
function OctoBuffer:async_fetch_taggable_users()
  local users = self.taggable_users or {}

  -- add participants
  for _, p in pairs(self.node.participants) do
    table.insert(users, p.login)
  end

  -- add comment authors
  for _, c in pairs(self.commentsMetadata) do
    table.insert(users, c.author)
  end

  -- add repo contributors
  gh.run {
    args = { "api", string.format("repos/%s/contributors", self.repo) },
    cb = function(response)
      if not utils.is_blank(response) then
        local resp = vim.fn.json_decode(response)
        for _, contributor in ipairs(resp) do
          table.insert(users, contributor.login)
        end
        self.taggable_users = users
      end
    end,
  }
end

-- This function fetches the issues in the repo so they can be used for
-- completion.
function OctoBuffer:async_fetch_issues()
  gh.run {
    args = { "api", string.format("repos/%s/issues", self.repo) },
    cb = function(response)
      local issues_metadata = {}
      local resp = vim.fn.json_decode(response)
      for _, issue in ipairs(resp) do
        table.insert(issues_metadata, { number = issue.number, title = issue.title })
      end
      octo_repo_issues[self.repo] = issues_metadata
    end,
  }
end

function OctoBuffer:save()
  local bufnr = vim.api.nvim_get_current_buf()

  -- collect comment metadata
  self:update_metadata()

  -- title & body
  if self.kind == "issue" or self.kind == "pull" then
    M.do_save_title_and_body(self)
  end

  -- comments
  local comments = self.commentsMetadata
  for _, comment in ipairs(comments) do
    if comment.body ~= comment.savedBody then
      if comment.id == -1 then
        if comment.kind == "IssueComment" then
          M.do_add_issue_comment(self, comment)
        elseif comment.kind == "PullRequestReviewComment" then
          if comment.replyTo and comment.replyTo ~= vim.NIL then
            M.do_add_thread_comment(self, comment)
          else
            M.do_add_new_thread(self, comment)
          end
        end
      else
        M.do_update_comment(self, comment)
      end
    end
  end

  -- reset modified option
  vim.api.nvim_buf_set_option(bufnr, "modified", false)
end

function M.do_save_title_and_body(buffer)
  local title_metadata = buffer.titleMetadata
  local desc_metadata = buffer.bodyMetadata
  local id = buffer.node.id
  if title_metadata.dirty or desc_metadata.dirty then
    -- trust but verify
    if string.find(title_metadata.body, "\n") then
      vim.api.nvim_err_writeln "Title can't contains new lines"
      return
    elseif title_metadata.body == "" then
      vim.api.nvim_err_writeln "Title can't be blank"
      return
    end

    local query
    if buffer:isIssue() then
      query = graphql("update_issue_mutation", id, title_metadata.body, desc_metadata.body)
    elseif buffer:isPullRequest() then
      query = graphql("update_pull_request_mutation", id, title_metadata.body, desc_metadata.body)
    end
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          local obj
          if buffer:isPullRequest() then
            obj = resp.data.updatePullRequest.pullRequest
          elseif buffer:isIssue() then
            obj = resp.data.updateIssue.issue
          end
          if title_metadata.body == obj.title then
            title_metadata.savedBody = obj.title
            title_metadata.dirty = false
            buffer.titleMetadata = title_metadata
          end

          if desc_metadata.body == obj.body then
            desc_metadata.savedBody = obj.body
            desc_metadata.dirty = false
            buffer.bodyMetadata = desc_metadata
          end

          buffer:render_signcolumn()
          utils.notify("Saved!", 1)
        end
      end,
    }
  end
end

function M.do_add_issue_comment(buffer, comment)
  -- create new issue comment
  local id = buffer.node.id
  local add_query = graphql("add_issue_comment_mutation", id, comment.body)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", add_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local respBody = resp.data.addComment.commentEdge.node.body
        local respId = resp.data.addComment.commentEdge.node.id
        if vim.fn.trim(comment.body) == vim.fn.trim(respBody) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = respId
              comments[i].savedBody = respBody
              comments[i].dirty = false
              break
            end
          end
          buffer:render_signcolumn()
        end
      end
    end,
  }
end

function M.do_add_thread_comment(buffer, comment)
  -- create new thread reply
  local query = graphql("add_pull_request_review_comment_mutation", comment.replyTo, comment.body, comment.reviewId)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_comment = resp.data.addPullRequestReviewComment.comment
        local comment_end
        if vim.fn.trim(comment.body) == vim.fn.trim(resp_comment.body) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = resp_comment.id
              comments[i].savedBody = resp_comment.body
              comments[i].dirty = false
              comment_end = comments[i].endLine
              break
            end
          end

          local threads = resp_comment.pullRequest.reviewThreads.nodes
          local review = require("octo.reviews").get_current_review()
          if review then
            review:update_threads(threads)
          end

          buffer:render_signcolumn()

          -- update thread map
          local thread_id
          for _, thread in ipairs(threads) do
            for _, c in ipairs(thread.comments.nodes) do
              if c.id == resp_comment.id then
                thread_id = thread.id
                break
              end
            end
          end
          local mark_id
          for markId, threadMetadata in pairs(buffer.threadsMetadata) do
            if threadMetadata.threadId == thread_id then
              mark_id = markId
            end
          end
          local extmark = vim.api.nvim_buf_get_extmark_by_id(
            buffer.bufnr,
            constants.OCTO_THREAD_NS,
            tonumber(mark_id),
            { details = true }
          )
          local thread_start = extmark[1]
          -- update extmark
          vim.api.nvim_buf_del_extmark(buffer.bufnr, constants.OCTO_THREAD_NS, tonumber(mark_id))
          local thread_mark_id = vim.api.nvim_buf_set_extmark(buffer.bufnr, constants.OCTO_THREAD_NS, thread_start, 0, {
            end_line = comment_end + 2,
            end_col = 0,
          })
          buffer.threadsMetadata[tostring(thread_mark_id)] = buffer.threadsMetadata[tostring(mark_id)]
          buffer.threadsMetadata[tostring(mark_id)] = nil
        end
      end
    end,
  }
end

function M.do_add_new_thread(buffer, comment)
  --TODO: How to create a new thread on a line where there is already one
  -- create new thread
  local query
  if comment.snippetStartLine == comment.snippetEndLine then
    query = graphql(
      "add_pull_request_review_thread_mutation",
      comment.reviewId,
      comment.body,
      comment.path,
      comment.diffSide,
      comment.snippetStartLine
    )
  else
    query = graphql(
      "add_pull_request_review_multiline_thread_mutation",
      comment.reviewId,
      comment.body,
      comment.path,
      comment.diffSide,
      comment.diffSide,
      comment.snippetStartLine,
      comment.snippetEndLine
    )
  end
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_comment = resp.data.addPullRequestReviewThread.thread.comments.nodes[1]
        if vim.fn.trim(comment.body) == vim.fn.trim(resp_comment.body) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = resp_comment.id
              comments[i].savedBody = resp_comment.body
              comments[i].dirty = false
              break
            end
          end
          local threads = resp.data.addPullRequestReviewThread.thread.pullRequest.reviewThreads.nodes
          local review = require("octo.reviews").get_current_review()
          if review then
            review:update_threads(threads)
          end
          buffer:render_signcolumn()
        end
      end
    end,
  }
end

function M.do_update_comment(buffer, comment)
  -- update comment/reply
  local update_query
  if comment.kind == "IssueComment" then
    update_query = graphql("update_issue_comment_mutation", comment.id, comment.body)
  elseif comment.kind == "PullRequestReviewComment" then
    update_query = graphql("update_pull_request_review_comment_mutation", comment.id, comment.body)
  elseif comment.kind == "PullRequestReview" then
    update_query = graphql("update_pull_request_review_mutation", comment.id, comment.body)
  end
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", update_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_comment
        if comment.kind == "IssueComment" then
          resp_comment = resp.data.updateIssueComment.issueComment
        elseif comment.kind == "PullRequestReviewComment" then
          resp_comment = resp.data.updatePullRequestReviewComment.pullRequestReviewComment
          local threads =
            resp.data.updatePullRequestReviewComment.pullRequestReviewComment.pullRequest.reviewThreads.nodes
          local review = require("octo.reviews").get_current_review()
          if review then
            review:update_threads(threads)
          end
        elseif comment.kind == "PullRequestReview" then
          resp_comment = resp.data.updatePullRequestReview.pullRequestReview
        end
        if resp_comment and vim.fn.trim(comment.body) == vim.fn.trim(resp_comment.body) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if c.id == comment.id then
              comments[i].savedBody = comment.body
              comments[i].dirty = false
              break
            end
          end
          buffer:render_signcolumn()
        end
      end
    end,
  }
end

function OctoBuffer:update_metadata()
  if not self.ready then
    return
  end
  local metadata_objs = {}
  if self.kind == "issue" or self.kind == "pull" then
    table.insert(metadata_objs, self.titleMetadata)
    table.insert(metadata_objs, self.bodyMetadata)
  end
  for _, m in ipairs(self.commentsMetadata) do
    table.insert(metadata_objs, m)
  end

  for _, metadata in ipairs(metadata_objs) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(
      self.bufnr,
      constants.OCTO_COMMENT_NS,
      metadata.extmark,
      { details = true }
    )
    local start_line, end_line, text = utils.get_extmark_region(self.bufnr, mark)
    metadata.body = text
    metadata.startLine = start_line
    metadata.endLine = end_line
    metadata.dirty = vim.fn.trim(metadata.body) ~= vim.fn.trim(metadata.savedBody) and true or false
  end
end

function OctoBuffer:render_signcolumn()
  if not self.ready then
    return
  end
  local issue_dirty = false

  -- update comment metadata (lines, etc.)
  self:update_metadata()

  -- clear all signs
  signs.unplace(self.bufnr)

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(self.bufnr, constants.OCTO_EMPTY_MSG_VT_NS, 0, -1)

  local metadata
  if self.kind == "issue" or self.kind == "pull" then
    -- title
    metadata = self.titleMetadata
    if metadata then
      if metadata.dirty then
        issue_dirty = true
      end
      signs.place_signs(self.bufnr, metadata.startLine, metadata.endLine, metadata.dirty)
    end

    -- description
    metadata = self.bodyMetadata
    if metadata then
      if metadata.dirty then
        issue_dirty = true
      end
      signs.place_signs(self.bufnr, metadata.startLine, metadata.endLine, metadata.dirty)

      -- description virtual text
      if utils.is_blank(metadata.body) then
        local desc_vt = { { constants.NO_BODY_MSG, "OctoEmpty" } }
        writers.write_virtual_text(self.bufnr, constants.OCTO_EMPTY_MSG_VT_NS, metadata.startLine, desc_vt)
      end
    end
  end

  -- comments
  local comments_metadata = self.commentsMetadata
  for _, comment_metadata in ipairs(comments_metadata) do
    metadata = comment_metadata
    if metadata then
      if metadata.dirty then
        issue_dirty = true
      end
      signs.place_signs(self.bufnr, metadata.startLine, metadata.endLine, metadata.dirty)

      -- comment virtual text
      if utils.is_blank(metadata.body) then
        local comment_vt = { { constants.NO_BODY_MSG, "OctoEmpty" } }
        writers.write_virtual_text(self.bufnr, constants.OCTO_EMPTY_MSG_VT_NS, metadata.startLine, comment_vt)
      end
    end
  end

  -- reset modified option
  if not issue_dirty then
    vim.api.nvim_buf_set_option(self.bufnr, "modified", false)
  end
end

function OctoBuffer:isReviewThread()
  return self.kind == "reviewthread"
end

function OctoBuffer:isPullRequest()
  return self.kind == "pull"
end

function OctoBuffer:isIssue()
  return self.kind == "issue"
end

function OctoBuffer:isRepo()
  return self.kind == "repo"
end

return M
