local BodyMetadata = require("octo.model.body-metadata").BodyMetadata
local TitleMetadata = require("octo.model.title-metadata").TitleMetadata
local autocmds = require "octo.autocmds"
local config = require "octo.config"
local constants = require "octo.constants"
local folds = require "octo.folds"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local mutations = require "octo.gh.mutations"
local signs = require "octo.ui.signs"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local vim = vim

local M = {}

---@alias octo.NodeKind "issue" | "pull" | "discussion" | "repo" | "release"

---@class OctoBuffer
---@field bufnr integer
---@field number integer
---@field repo string
---@field kind octo.NodeKind|"reviewthread"
---@field titleMetadata TitleMetadata
---@field bodyMetadata BodyMetadata
---@field commentsMetadata CommentMetadata[]
---@field threadsMetadata ThreadMetadata[]
---@field private node octo.PullRequest|octo.Issue|octo.Release|octo.Discussion|octo.Repository
---@field taggable_users? string[]
---@field owner? string
---@field name? string
local OctoBuffer = {}
OctoBuffer.__index = OctoBuffer

---OctoBuffer constructor.
---@param opts {
---  bufnr: integer,
---  number: integer,
---  repo: string,
---  node: octo.PullRequest|octo.Issue|octo.Release|octo.Repository|octo.Discussion,
---  kind: string,
---  commentsMetadata: CommentMetadata[],
---  threadsMetadata: ThreadMetadata[],
---}
---@return OctoBuffer
function OctoBuffer:new(opts)
  ---@type OctoBuffer
  local this = {
    bufnr = opts.bufnr or vim.api.nvim_get_current_buf(),
    number = opts.number,
    repo = opts.repo,
    node = opts.node,
    titleMetadata = TitleMetadata:new(),
    bodyMetadata = BodyMetadata:new(),
    commentsMetadata = opts.commentsMetadata or {},
    threadsMetadata = opts.threadsMetadata or {},
    kind = opts.kind,
  }
  if this.repo then
    this.owner, this.name = utils.split_repo(this.repo)
  end

  if this.node and this.node.commits then
    this.kind = "pull"
    this.taggable_users = { this.node.author.login }
  elseif this.node and this.number then
    this.kind = opts.kind or "issue"
    if not utils.is_blank(this.node.author) then
      this.taggable_users = { this.node.author.login }
    end
  elseif this.node and not this.number then
    this.kind = opts.kind or "repo"
  else
    this.kind = "reviewthread"
  end

  setmetatable(this, self)
  octo_buffers[this.bufnr] = this
  return this
end

M.OctoBuffer = OctoBuffer

---Apply the buffer mappings
function OctoBuffer:apply_mappings()
  ---@type string
  local kind = self.kind
  if self.kind == "pull" then
    kind = "pull_request"
  elseif self.kind == "reviewthread" then
    kind = "review_thread"
  end
  utils.apply_mappings(kind, self.bufnr)
end

---Clears the buffer
function OctoBuffer:clear()
  -- clear buffer
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})

  -- delete extmarks
  local extmarks = vim.api.nvim_buf_get_extmarks(self.bufnr, constants.OCTO_COMMENT_NS, 0, -1, {})
  for _, m in ipairs(extmarks) do
    vim.api.nvim_buf_del_extmark(self.bufnr, constants.OCTO_COMMENT_NS, m[1])
  end
end

---Writes a repo to the buffer
function OctoBuffer:render_repo()
  self:clear()
  writers.write_repo(self.bufnr, self:repository())

  -- reset modified option
  vim.bo[self.bufnr].modified = false

  self.ready = true
end

function OctoBuffer:render_release()
  self:clear()
  writers.write_release(self.bufnr, self:release())
  vim.bo[self.bufnr].modified = false
  self.ready = true
end

function OctoBuffer:render_discussion()
  self:clear()

  local obj = self:discussion()
  local state = obj.closed and "CLOSED" or "OPEN"
  writers.write_title(self.bufnr, tostring(obj.title), 1)
  writers.write_state(self.bufnr, state, self.number)
  writers.write_discussion_details(self.bufnr, obj)
  writers.write_body(self.bufnr, obj, 13)

  -- write body reactions
  local reaction_line ---@type integer?
  if utils.count_reactions(obj.reactionGroups) > 0 then
    local line = vim.api.nvim_buf_line_count(self.bufnr) + 1
    writers.write_block(self.bufnr, { "", "" }, line)
    reaction_line = writers.write_reactions(self.bufnr, obj.reactionGroups, line)
  end
  self.bodyMetadata.reactionGroups = obj.reactionGroups
  self.bodyMetadata.reactionLine = reaction_line

  if obj.answer ~= vim.NIL then
    local line = vim.api.nvim_buf_line_count(self.bufnr) + 1
    writers.write_discussion_answer(self.bufnr, obj, line)
    writers.write_block(self.bufnr, { "" })
  end

  for _, comment in ipairs(obj.comments.nodes) do
    writers.write_comment(self.bufnr, comment, "DiscussionComment")
    if comment.replies.totalCount > 0 then
      for _, reply in ipairs(comment.replies.nodes) do
        writers.write_comment(self.bufnr, reply, "DiscussionComment")
      end
    end
  end

  vim.bo[self.bufnr].filetype = "octo"

  self.ready = true
end

---Writes an issue or pull request to the buffer.
function OctoBuffer:render_issue()
  self:clear()
  local obj = self:isPullRequest() and self:pullRequest() or self:issue()

  -- write title
  writers.write_title(self.bufnr, obj.title, 1)

  -- write details in buffer
  writers.write_details(self.bufnr, obj)

  -- write issue/pr status
  local state = utils.get_displayed_state(self.kind == "issue", obj.state, obj.stateReason)
  writers.write_state(self.bufnr, state:upper(), self.number)

  -- write body
  writers.write_body(self.bufnr, obj)

  -- write body reactions
  local reaction_line ---@type integer?
  if utils.count_reactions(obj.reactionGroups) > 0 then
    local line = vim.api.nvim_buf_line_count(self.bufnr) + 1
    writers.write_block(self.bufnr, { "", "" }, line)
    reaction_line = writers.write_reactions(self.bufnr, obj.reactionGroups, line)
  end
  self.bodyMetadata.reactionGroups = obj.reactionGroups
  self.bodyMetadata.reactionLine = reaction_line

  -- write timeline items
  local unrendered_labeled_events = {} ---@type octo.fragments.LabeledEvent[]
  local unrendered_unlabeled_events = {} ---@type octo.fragments.UnlabeledEvent[]
  local unrendered_subissue_added_events = {} ---@type octo.fragments.SubIssueAddedEvent[]
  local unrendered_subissue_removed_events = {} ---@type octo.fragments.SubIssueRemovedEvent[]
  local commits = {} ---@type octo.fragments.PullRequestCommit[]
  local prev_is_event = false

  ---@type (octo.PullRequestTimelineItem|octo.IssueTimelineItem)[]
  local timeline_nodes = {}
  for _, item in ipairs(obj.timelineItems.nodes) do
    if item ~= vim.NIL then
      table.insert(timeline_nodes, item)
    end
  end

  --- Empty timeline node to ensure the last
  --- labeled/unlabeled events or subissues events are rendered
  table.insert(timeline_nodes, {})

  ---@param item? octo.PullRequestTimelineItem|octo.IssueTimelineItem
  local function render_accumulated_events(item)
    if (not item or item.__typename ~= "LabeledEvent") and #unrendered_labeled_events > 0 then
      writers.write_labeled_events(self.bufnr, unrendered_labeled_events, "added")
      unrendered_labeled_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "UnlabeledEvent") and #unrendered_unlabeled_events > 0 then
      writers.write_labeled_events(self.bufnr, unrendered_unlabeled_events, "removed")
      unrendered_unlabeled_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "SubIssueAddedEvent") and #unrendered_subissue_added_events > 0 then
      writers.write_subissue_events(self.bufnr, unrendered_subissue_added_events, "added")
      unrendered_subissue_added_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "SubIssueRemovedEvent") and #unrendered_subissue_removed_events > 0 then
      writers.write_subissue_events(self.bufnr, unrendered_subissue_removed_events, "removed")
      unrendered_subissue_removed_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "PullRequestCommit") and #commits > 0 then
      writers.write_commits(self.bufnr, commits)
      commits = {}
      prev_is_event = true
    end
  end

  for _, item in ipairs(timeline_nodes) do
    render_accumulated_events(item)
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
        for _, reviewThread in ipairs(self:pullRequest().reviewThreads.nodes) do
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
          review_end = writers.write_threads(self.bufnr, threads)
          folds.create(self.bufnr, review_start + 1, review_end, true)
        end
        writers.write_block(self.bufnr, { "" })
      else
        writers.write_review_decision(self.bufnr, item)
      end
      prev_is_event = false
    elseif item.__typename == "AssignedEvent" then
      writers.write_assigned_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "PullRequestCommit" then
      table.insert(commits, item)
      prev_is_event = true
    elseif item.__typename == "MergedEvent" then
      writers.write_merged_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ClosedEvent" then
      writers.write_closed_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReopenedEvent" then
      writers.write_reopened_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "LabeledEvent" then
      table.insert(unrendered_labeled_events, item)
    elseif item.__typename == "UnlabeledEvent" then
      table.insert(unrendered_unlabeled_events, item)
    elseif item.__typename == "ReviewRequestedEvent" then
      writers.write_review_requested_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReviewRequestRemovedEvent" then
      writers.write_review_request_removed_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReviewDismissedEvent" then
      writers.write_review_dismissed_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "RenamedTitleEvent" then
      writers.write_renamed_title_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ConnectedEvent" then
      writers.write_connected_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "CrossReferencedEvent" then
      writers.write_cross_referenced_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReferencedEvent" then
      writers.write_referenced_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "MilestonedEvent" then
      writers.write_milestoned_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "DemilestonedEvent" then
      writers.write_demilestoned_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "PinnedEvent" then
      writers.write_pinned_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "UnpinnedEvent" then
      writers.write_unpinned_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "SubIssueAddedEvent" then
      table.insert(unrendered_subissue_added_events, item)
    elseif item.__typename == "SubIssueRemovedEvent" then
      table.insert(unrendered_subissue_removed_events, item)
    elseif item.__typename == "ParentIssueAddedEvent" then
      writers.write_parent_issue_added_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ParentIssueRemovedEvent" then
      writers.write_parent_issue_removed_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "IssueTypeAddedEvent" then
      writers.write_issue_type_added_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "IssueTypeRemovedEvent" then
      writers.write_issue_type_removed_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "IssueTypeChangedEvent" then
      writers.write_issue_type_changed_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ConvertToDraftEvent" then
      writers.write_convert_to_draft_event(self.bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReadyForReviewEvent" then
      writers.write_ready_for_review_event(self.bufnr, item)
      prev_is_event = true
    end
  end
  render_accumulated_events()

  if prev_is_event then
    writers.write_block(self.bufnr, { "" })
  end

  -- drop undo history
  utils.clear_history()

  -- reset modified option
  vim.bo[self.bufnr].modified = false

  self.ready = true
end

---Draws review threads
---@param threads octo.ReviewThread[]
function OctoBuffer:render_threads(threads)
  self:clear()
  writers.write_threads(self.bufnr, threads)
  vim.bo[self.bufnr].modified = false
  self.ready = true
end

---Configures the buffer
function OctoBuffer:configure()
  -- configure buffer
  vim.api.nvim_buf_call(self.bufnr, function()
    vim.cmd [[setlocal filetype=octo]]
    vim.cmd [[setlocal buftype=acwrite]]
    vim.cmd [[setlocal omnifunc=v:lua.octo_omnifunc]]
    vim.cmd [[setlocal conceallevel=2]]
    vim.cmd [[setlocal nonumber norelativenumber nocursorline wrap]]

    if config.values.ui.use_signcolumn then
      vim.cmd [[setlocal signcolumn=yes]]
      autocmds.update_signs(self.bufnr)
    end
    if config.values.ui.use_statuscolumn then
      vim.opt_local.statuscolumn = [[%!v:lua.require'octo.ui.statuscolumn'.statuscolumn()]]
      autocmds.update_signs(self.bufnr)
    end
    if config.values.ui.use_foldtext then
      vim.opt_local.foldtext = [[v:lua.require'octo.folds'.foldtext()]]
    end
  end)

  self:apply_mappings()
end

---Accumulates all the taggable users into a single list that
--gets set as a buffer variable `taggable_users`. If this list of users
---is needed synchronously, this function will need to be refactored.
---The list of taggable users should contain:
--  - The PR author
--  - The authors of all the existing comments
--  - The contributors of the repo
function OctoBuffer:async_fetch_taggable_users()
  local users = self.taggable_users or {}

  -- add participants
  for _, p in ipairs(self.node.participants.nodes) do
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
        ---@type { login: string }[]
        local resp = vim.json.decode(response)
        for _, contributor in ipairs(resp) do
          table.insert(users, contributor.login)
        end
        self.taggable_users = users
      end
    end,
  }
end

---Fetches the issues in the repo so they can be used for completion.
function OctoBuffer:async_fetch_issues()
  gh.run {
    args = { "api", string.format("repos/%s/issues", self.repo) },
    cb = function(response)
      local issues_metadata = {} ---@type { number: integer, title: string }[]
      ---@type { number: integer, title: string }[]
      local resp = vim.json.decode(response)
      for _, issue in ipairs(resp) do
        issues_metadata[#issues_metadata + 1] = { number = issue.number, title = issue.title }
      end
      octo_repo_issues[self.repo] = issues_metadata
    end,
  }
end

---Syncs all the comments/title/body with GitHub
function OctoBuffer:save()
  local bufnr = vim.api.nvim_get_current_buf()

  -- collect comment metadata
  self:update_metadata()

  -- title & body
  if self.kind == "issue" or self.kind == "pull" or self.kind == "discussion" then
    self:do_save_title_and_body()
  end

  -- comments
  for _, comment_metadata in ipairs(self.commentsMetadata) do
    if comment_metadata.body ~= comment_metadata.savedBody then
      if comment_metadata.id == -1 then
        -- we use -1 as an indicator for new comments for which we dont currently have a GH id
        if comment_metadata.kind == "IssueComment" then
          self:do_add_issue_comment(comment_metadata)
        elseif comment_metadata.kind == "DiscussionComment" then
          self:do_add_discussion_comment(comment_metadata)
        elseif comment_metadata.kind == "PullRequestReviewComment" then
          if not utils.is_blank(comment_metadata.replyTo) then
            -- comment is a reply to a thread comment
            self:do_add_thread_comment(comment_metadata)
          else
            -- comment starts a new thread of comments
            self:do_add_new_thread(comment_metadata)
          end
        elseif comment_metadata.kind == "PullRequestComment" then
          self:do_add_pull_request_comment(comment_metadata)
        end
      else
        -- comment is an existing comment
        self:do_update_comment(comment_metadata)
      end
    end
  end

  -- reset modified option
  vim.bo[bufnr].modified = false
end

---Sync issue/PR/discussion title and body with GitHub
function OctoBuffer:do_save_title_and_body()
  local title_metadata = self.titleMetadata
  local desc_metadata = self.bodyMetadata
  local node = self:isIssue() and self:issue() or self:isPullRequest() and self:pullRequest() or self:discussion()
  local id = node.id
  if title_metadata.dirty or desc_metadata.dirty then
    -- trust but verify
    if string.find(title_metadata.body, "\n") then
      utils.print_err "Title can't contains new lines"
      return
    elseif title_metadata.body == "" then
      utils.print_err "Title can't be blank"
      return
    end

    local query ---@type string
    if self:isIssue() then
      query = graphql("update_issue_mutation", id, title_metadata.body, desc_metadata.body)
    elseif self:isPullRequest() then
      query = graphql("update_pull_request_mutation", id, title_metadata.body, desc_metadata.body)
    elseif self:isDiscussion() then
      query = graphql("update_discussion_mutation", id, title_metadata.body, desc_metadata.body)
    end
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.print_err(stderr)
        elseif output then
          ---@type octo.mutations.UpdatePullRequest|octo.mutations.UpdateIssue|octo.mutations.UpdateDiscussion
          local resp = vim.json.decode(output)
          local obj ---@type { title: string, body: string }

          if self:isPullRequest() then
            obj = resp.data.updatePullRequest.pullRequest
          elseif self:isIssue() then
            obj = resp.data.updateIssue.issue
          elseif self:isDiscussion() then
            obj = resp.data.updateDiscussion.discussion
          end

          if title_metadata.body == obj.title then
            title_metadata.savedBody = obj.title
            title_metadata.dirty = false
            self.titleMetadata = title_metadata
          end

          if desc_metadata.body == obj.body then
            desc_metadata.savedBody = obj.body
            desc_metadata.dirty = false
            self.bodyMetadata = desc_metadata
          end

          self:render_signs()
          utils.info "Saved!"
        end
      end,
    }
  end
end

---@param comment_metadata CommentMetadata
function OctoBuffer:do_add_discussion_comment(comment_metadata)
  local f = {
    discussion_id = self:discussion().id,
    body = comment_metadata.body,
  }
  if comment_metadata.replyTo then
    f.reply_to_id = comment_metadata.replyTo
  end
  gh.api.graphql {
    query = mutations.add_discussion_comment,
    f = f,
    jq = ".data.addDiscussionComment.comment",
    opts = {
      cb = gh.create_callback {
        failure = utils.print_err,
        success = function(output)
          local resp = vim.json.decode(output)

          if utils.trim(comment_metadata.body) ~= utils.trim(resp.body) then
            return
          end

          for i, comment in ipairs(self.commentsMetadata) do
            if comment.id == -1 then
              self.commentsMetadata[i].id = resp.id
              self.commentsMetadata[i].savedBody = resp.body
              self.commentsMetadata[i].dirty = false
              break
            end
          end

          self:render_signs()
        end,
      },
    },
  }
end

---Add a new comment to the issue/PR
---@param comment_metadata CommentMetadata
function OctoBuffer:do_add_issue_comment(comment_metadata)
  -- create new issue comment
  local obj = self:isIssue() and self:issue() or self:pullRequest()
  local id = obj.id
  local add_query = graphql("add_issue_comment_mutation", id, comment_metadata.body)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", add_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.print_err(stderr)
      elseif output then
        ---@type octo.mutations.AddIssueComment
        local resp = vim.json.decode(output)
        local respBody = resp.data.addComment.commentEdge.node.body
        local respId = resp.data.addComment.commentEdge.node.id
        if utils.trim(comment_metadata.body) == utils.trim(respBody) then
          local comments = self.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = respId
              comments[i].savedBody = respBody
              comments[i].dirty = false
              break
            end
          end
          self:render_signs()
        end
      end
    end,
  }
end

---Replies to a review comment thread
---@param comment_metadata CommentMetadata
function OctoBuffer:do_add_thread_comment(comment_metadata)
  -- create new thread reply
  local query = graphql(
    "add_pull_request_review_comment_mutation",
    comment_metadata.replyTo,
    comment_metadata.body,
    comment_metadata.reviewId
  )
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.print_err(stderr)
      elseif output then
        ---@type octo.mutations.AddPullRequestReviewComment
        local resp = vim.json.decode(output)
        local resp_comment = resp.data.addPullRequestReviewComment.comment
        local comment_end ---@type integer
        if utils.trim(comment_metadata.body) == utils.trim(resp_comment.body) then
          local comments = self.commentsMetadata
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

          self:render_signs()

          -- update thread map
          local thread_id ---@type string
          for _, thread in ipairs(threads) do
            for _, c in ipairs(thread.comments.nodes) do
              if c.id == resp_comment.id then
                thread_id = thread.id
                break
              end
            end
          end
          local mark_id ---@type integer
          for markId, threadMetadata in pairs(self.threadsMetadata) do
            if threadMetadata.threadId == thread_id then
              mark_id = markId
            end
          end
          local extmark = vim.api.nvim_buf_get_extmark_by_id(
            self.bufnr,
            constants.OCTO_THREAD_NS,
            tonumber(mark_id) --[[@as integer]],
            { details = true }
          )
          local thread_start = extmark[1]
          -- update extmark
          vim.api.nvim_buf_del_extmark(self.bufnr, constants.OCTO_THREAD_NS, tonumber(mark_id) --[[@as integer]])
          local thread_mark_id = vim.api.nvim_buf_set_extmark(self.bufnr, constants.OCTO_THREAD_NS, thread_start, 0, {
            end_line = comment_end + 2,
            end_col = 0,
          })
          self.threadsMetadata[tostring(thread_mark_id)] = self.threadsMetadata[tostring(mark_id)]
          self.threadsMetadata[tostring(mark_id)] = nil
        end
      end
    end,
  }
end

---Adds a new review comment thread to the current review.
---@param comment_metadata CommentMetadata
---@return nil
function OctoBuffer:do_add_new_thread(comment_metadata)
  --TODO: How to create a new thread on a line where there is already one

  local review = require("octo.reviews").get_current_review()
  if not review then
    return
  end
  local layout = review.layout
  local file = layout:get_current_file()
  if not file then
    utils.error "No file selected"
    return
  end
  local review_level = review:get_level()
  local isMultiline = true
  if comment_metadata.snippetStartLine == comment_metadata.snippetEndLine then
    isMultiline = false
  end

  -- create new thread
  if review_level == "PR" then
    local query ---@type string
    if isMultiline then
      query = graphql(
        "add_pull_request_review_multiline_thread_mutation",
        comment_metadata.reviewId,
        comment_metadata.body,
        comment_metadata.path,
        comment_metadata.diffSide,
        comment_metadata.diffSide,
        comment_metadata.snippetStartLine,
        comment_metadata.snippetEndLine
      )
    else
      query = graphql(
        "add_pull_request_review_thread_mutation",
        comment_metadata.reviewId,
        comment_metadata.body,
        comment_metadata.path,
        comment_metadata.diffSide,
        comment_metadata.snippetStartLine
      )
    end
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.print_err(stderr)
        elseif output then
          ---@type octo.mutations.AddPullRequestReviewThread
          local resp_data = vim.json.decode(output)
          local resp = resp_data.data.addPullRequestReviewThread

          if utils.is_blank(resp) then
            utils.error "Failed to create thread"
            return
          end

          -- Register new thread id
          local threads = self.threadsMetadata
          local new_thread = nil
          for _, t in pairs(threads) do
            if tonumber(t.threadId) == -1 then
              new_thread = t
              break
            end
          end

          -- Register new comment data
          local new_comment = resp.thread.comments.nodes[1]
          if new_thread then
            new_thread.threadId = resp.thread.id
            new_thread.replyTo = new_comment.id
          end
          if utils.trim(comment_metadata.body) == utils.trim(new_comment.body) then
            local comments = self.commentsMetadata
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = new_comment.id
                comments[i].savedBody = new_comment.body
                comments[i].dirty = false
                break
              end
            end
            local review_threads = resp.thread.pullRequest.reviewThreads.nodes
            if review then
              review:update_threads(review_threads)
            end
            self:render_signs()
          end
        end
      end,
    }
  elseif review_level == "COMMIT" then
    if isMultiline then
      utils.error "Can't create a multiline comment at the commit level"
      return
    else
      -- get the line number the comment is on
      local line ---@type integer
      for _, thread in
        ipairs(vim.tbl_values(self.threadsMetadata) --[[@as ThreadMetadata[] ]])
      do
        if thread.threadId == -1 then
          line = thread.line
        end
      end

      -- we need to convert the line number to a diff line number (position)
      local position = line
      if file.status ~= "A" then
        -- for non-added files (modified), check we are in a valid comment range
        local diffhunks = {}
        local diffhunk = ""
        local left_comment_ranges, right_comment_ranges = {}, {}
        diffhunks, left_comment_ranges, right_comment_ranges =
          file.diffhunks, file.left_comment_ranges, file.right_comment_ranges
        local comment_ranges ---@type [integer, integer][]
        if not diffhunks then
          utils.error "Diff hunks not found"
          return
        end
        if comment_metadata.diffSide == "RIGHT" then
          if not right_comment_ranges then
            utils.error "Right comment ranges not found"
            return
          end
          comment_ranges = right_comment_ranges
        elseif comment_metadata.diffSide == "LEFT" then
          if not left_comment_ranges then
            utils.error "Left comment ranges not found"
            return
          end
          comment_ranges = left_comment_ranges
        end
        local idx, offset = 0, 0
        for i, range in ipairs(comment_ranges) do
          if range[1] <= line and range[2] >= line then
            diffhunk = diffhunks[i]
            idx = i
            break
          end
        end
        for i, hunk in ipairs(diffhunks) do
          if i < idx then
            offset = offset + #vim.split(hunk, "\n")
          end
        end
        if not vim.startswith(diffhunk, "@@") then
          diffhunk = "@@ " .. diffhunk
        end

        local map = utils.generate_line2position_map(diffhunk)
        if comment_metadata.diffSide == "RIGHT" then
          position = map.right_side_lines[tostring(line)]
        elseif comment_metadata.diffSide == "LEFT" then
          position = map.left_side_lines[tostring(line)]
        end
        position = position + offset - 1
      end

      local query = graphql(
        "add_pull_request_review_commit_thread_mutation",
        layout.right.commit,
        comment_metadata.body,
        comment_metadata.reviewId,
        comment_metadata.path,
        position
      )
      gh.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
          if stderr and not utils.is_blank(stderr) then
            utils.print_err(stderr)
          elseif output then
            ---@type octo.mutations.AddPullRequestReviewCommitThread
            local r = vim.json.decode(output)
            local resp = r.data.addPullRequestReviewComment
            if not utils.is_blank(resp.comment) then
              if utils.trim(comment_metadata.body) == utils.trim(resp.comment.body) then
                local comments = self.commentsMetadata
                for i, c in ipairs(comments) do
                  if tonumber(c.id) == -1 then
                    comments[i].id = resp.comment.id
                    comments[i].savedBody = resp.comment.body
                    comments[i].dirty = false
                    break
                  end
                end
                if review then
                  local threads = resp.comment.pullRequest.reviewThreads.nodes
                  review:update_threads(threads)
                end
                self:render_signs()
              end
            else
              utils.error "Failed to create thread"
              return
            end
          end
        end,
      }
    end
  end
end

---Replies a review thread w/o creating a new review
function OctoBuffer:do_add_pull_request_comment(comment_metadata)
  local current_review = require("octo.reviews").get_current_review()
  if not utils.is_blank(current_review) then
    utils.error "Please submit or discard the current review before adding a comment"
    return
  end
  gh.run {
    args = {
      "api",
      "--method",
      "POST",
      string.format("/repos/%s/pulls/%d/comments/%s/replies", self.repo, self.number, comment_metadata.replyToRest),
      "-f",
      string.format([[body=%s]], utils.escape_char(comment_metadata.body)),
      "--jq",
      ".",
    },
    headers = { "Accept: application/vnd.github.v3+json" },
    cb = function(output, stderr)
      if not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        if not utils.is_blank(resp) then
          if utils.trim(comment_metadata.body) == utils.trim(resp.body) then
            local comments = self.commentsMetadata
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = resp.id
                comments[i].savedBody = resp.body
                comments[i].dirty = false
                break
              end
            end
            self:render_signs()
          end
        else
          utils.error "Failed to create thread"
          return
        end
      end
    end,
  }
end

---Update a comment's metadata
---@param comment_metadata CommentMetadata
function OctoBuffer:do_update_comment(comment_metadata)
  -- update comment/reply
  local update_query ---@type string
  if comment_metadata.kind == "IssueComment" then
    update_query = graphql("update_issue_comment_mutation", comment_metadata.id, comment_metadata.body)
  elseif comment_metadata.kind == "PullRequestReviewComment" then
    update_query = graphql("update_pull_request_review_comment_mutation", comment_metadata.id, comment_metadata.body)
  elseif comment_metadata.kind == "PullRequestReview" then
    update_query = graphql("update_pull_request_review_mutation", comment_metadata.id, comment_metadata.body)
  elseif comment_metadata.kind == "DiscussionComment" then
    update_query = graphql("update_discussion_comment_mutation", comment_metadata.id, comment_metadata.body)
  end
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", update_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.print_err(stderr)
      elseif output then
        ---@type octo.mutations.UpdateIssueComment|octo.mutations.UpdateDiscussionComment|octo.mutations.UpdatePullRequestReviewComment|octo.mutations.UpdatePullRequestReview
        local resp = vim.json.decode(output)

        local resp_comment ---@type { body: string }?
        if comment_metadata.kind == "IssueComment" then
          resp_comment = resp.data.updateIssueComment.issueComment
        elseif comment_metadata.kind == "DiscussionComment" then
          resp_comment = resp.data.updateDiscussionComment.comment
        elseif comment_metadata.kind == "PullRequestReviewComment" then
          resp_comment = resp.data.updatePullRequestReviewComment.pullRequestReviewComment
          local threads =
            resp.data.updatePullRequestReviewComment.pullRequestReviewComment.pullRequest.reviewThreads.nodes
          local review = require("octo.reviews").get_current_review()
          if review then
            review:update_threads(threads)
          end
        elseif comment_metadata.kind == "PullRequestReview" then
          resp_comment = resp.data.updatePullRequestReview.pullRequestReview
        end

        if resp_comment and utils.trim(comment_metadata.body) == utils.trim(resp_comment.body) then
          local comments = self.commentsMetadata
          for i, c in ipairs(comments) do
            if c.id == comment_metadata.id then
              comments[i].savedBody = comment_metadata.body
              comments[i].dirty = false
              break
            end
          end
          self:render_signs()
        end
      end
    end,
  }
end

---Update the buffer metadata
function OctoBuffer:update_metadata()
  if not self.ready then
    return
  end
  local metadata_objs = {} ---@type (TitleMetadata|BodyMetadata|CommentMetadata)[]
  if self.kind == "issue" or self.kind == "pull" or self.kind == "discussion" then
    table.insert(metadata_objs, self.titleMetadata)
    table.insert(metadata_objs, self.bodyMetadata)
  end
  for _, m in ipairs(self.commentsMetadata) do
    table.insert(metadata_objs, m)
  end

  for _, metadata in ipairs(metadata_objs) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, { details = true })
    local start_line, end_line, text = utils.get_extmark_region(self.bufnr, mark)
    metadata.body = text
    metadata.startLine = start_line
    metadata.endLine = end_line
    metadata.dirty = utils.trim(metadata.body) ~= utils.trim(metadata.savedBody) and true or false
  end
end

---Renders the signs in the signcolumn or statuscolumn
function OctoBuffer:render_signs()
  local use_signcolumn = config.values.ui.use_signcolumn
  local use_statuscolumn = config.values.ui.use_statuscolumn
  if not self.ready or (not use_statuscolumn and not use_signcolumn) then
    return
  end

  local issue_dirty = false

  -- update comment metadata (lines, etc.)
  self:update_metadata()

  -- clear all signs
  signs.unplace(self.bufnr)

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(self.bufnr, constants.OCTO_EMPTY_MSG_VT_NS, 0, -1)

  local metadata ---@type (TitleMetadata|BodyMetadata|CommentMetadata)
  if self.kind == "issue" or self.kind == "pull" or self.kind == "discussion" then
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
    vim.bo[self.bufnr].modified = false
  end
end

--- Checks if the buffer represents a review comment thread
function OctoBuffer:isReviewThread()
  return self.kind == "reviewthread"
end

function OctoBuffer:isDiscussion()
  return self.kind == "discussion"
end

function OctoBuffer:discussion()
  assert(self:isDiscussion(), "Not a discussion buffer")
  return self.node --[[@as octo.Discussion]]
end

--- Checks if the buffer represents a Pull Request
function OctoBuffer:isPullRequest()
  return self.kind == "pull"
end

function OctoBuffer:pullRequest()
  assert(self:isPullRequest(), "Not a pull request buffer")
  return self.node --[[@as octo.PullRequest]]
end

--- Checks if the buffer represents an Issue
function OctoBuffer:isIssue()
  return self.kind == "issue"
end

function OctoBuffer:issue()
  assert(self:isIssue(), "Not an issue buffer")
  return self.node --[[@as octo.Issue]]
end

---Checks if the buffer represents a GitHub repo
function OctoBuffer:isRepo()
  return self.kind == "repo"
end

function OctoBuffer:repository()
  assert(self:isRepo(), "Not a repo buffer")
  return self.node --[[@as octo.Repository]]
end

function OctoBuffer:isRelease()
  return self.kind == "release"
end

function OctoBuffer:release()
  assert(self:isRelease(), "Not a release buffer")
  return self.node --[[@as octo.Release]]
end

---Gets the PR object for the current octo buffer with correct merge base
---@param callback function Callback function(pr) called with the PullRequest object
function OctoBuffer:get_pr(callback)
  if not self:isPullRequest() then
    utils.error "Not in a PR buffer"
    return
  end

  if not callback then
    utils.error "get_pr requires a callback function"
    return
  end

  local PullRequest = require "octo.model.pull-request"
  local bufnr = vim.api.nvim_get_current_buf()

  local opts = {
    bufnr = bufnr,
    repo = self.repo,
    head_repo = self:pullRequest().headRepository.nameWithOwner,
    head_ref_name = self:pullRequest().headRefName,
    number = self.number,
    id = self:pullRequest().id,
  }

  PullRequest.create_with_merge_base(opts, self:pullRequest(), callback)
end

--- Get a issue/PR comment at cursor (if any)
function OctoBuffer:get_comment_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return self:get_comment_at_line(cursor[1])
end

--- Get a issue/PR comment at a given line (if any)
function OctoBuffer:get_comment_at_line(line)
  for _, comment in ipairs(self.commentsMetadata) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, comment.extmark, { details = true })
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line + 1 <= line and end_line - 2 >= line then
      comment.bufferStartLine = start_line
      comment.bufferEndLine = end_line
      return comment
    end
  end
end

---Gets the issue/PR body at cursor (if any)
function OctoBuffer:get_body_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local metadata = self.bodyMetadata
  local mark =
    vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, { details = true })
  local start_line = mark[1] + 1
  local end_line = mark[3]["end_row"] + 1
  if start_line + 1 <= cursor[1] and end_line - 2 >= cursor[1] then
    return metadata, start_line, end_line
  end
end

---Gets the review thread at cursor (if any)
function OctoBuffer:get_thread_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return self:get_thread_at_line(cursor[1])
end

---Gets the review thread at a given line (if any)
---@param line integer
function OctoBuffer:get_thread_at_line(line)
  local thread_marks = vim.api.nvim_buf_get_extmarks(self.bufnr, constants.OCTO_THREAD_NS, 0, -1, { details = true })
  for _, mark in ipairs(thread_marks) do
    local thread = self.threadsMetadata[tostring(mark[1])]
    if thread then
      local startLine = mark[2] - 1
      local endLine = mark[4].end_row
      if startLine <= line and endLine >= line then
        thread.bufferStartLine = startLine
        thread.bufferEndLine = endLine
        return thread
      end
    end
  end
end

---Gets the reactions groups at cursor (if any)
function OctoBuffer:get_reactions_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local body_reaction_line = self.bodyMetadata.reactionLine
  if body_reaction_line and body_reaction_line == cursor[1] then
    return self.node.id
  end

  local comments_metadata = self.commentsMetadata
  if comments_metadata then
    for _, c in pairs(comments_metadata) do
      if c.reactionLine and c.reactionLine == cursor[1] then
        return c.id
      end
    end
  end
end

---Updates the reactions groups at cursor (if any)
---@param reaction_groups octo.ReactionGroupsFragment.reactionGroups[]
---@param reaction_line integer
function OctoBuffer:update_reactions_at_cursor(reaction_groups, reaction_line)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local reactions_count = 0
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count + 1
    end
  end

  local comments = self.commentsMetadata
  for i, comment in ipairs(comments) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, comment.extmark, { details = true })
    local start_line = mark[1] + 1
    local end_line = mark[3].end_row + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      -- cursor located in the body of a comment
      -- update reaction groups
      comments[i].reactionGroups = reaction_groups

      -- update reaction line
      if not comments[i].reactionLine and reactions_count > 0 then
        comments[i].reactionLine = reaction_line
      elseif reactions_count == 0 then
        comments[i].reactionLine = nil
      end
      return
    end
  end

  -- cursor not located at any comment, so updating issue
  --  update reaction groups
  self.bodyMetadata.reactionGroups = reaction_groups
  local body_reaction_line = self.bodyMetadata.reactionLine
  if not body_reaction_line and reactions_count > 0 then
    self.bodyMetadata.reactionLine = reaction_line
  elseif reactions_count == 0 then
    self.bodyMetadata.reactionLine = nil
  end
end

return M
