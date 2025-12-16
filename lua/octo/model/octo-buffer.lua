local BodyMetadata = require("octo.model.body-metadata").BodyMetadata
local TitleMetadata = require("octo.model.title-metadata").TitleMetadata
local autocmds = require "octo.autocmds"
local config = require "octo.config"
local constants = require "octo.constants"
local folds = require "octo.folds"
local gh = require "octo.gh"
local headers = require "octo.gh.headers"
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
---@field taggable_users? string[] list of taggable users for the buffer. Trigger with @
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
    this.taggable_users = { this.node.author.login, "copilot" }
  elseif this.node and this.number then
    this.kind = opts.kind or "issue"
    if not utils.is_blank(this.node.author) then
      this.taggable_users = { this.node.author.login, "copilot" }
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
  writers.write_timeline_items(self.bufnr, obj)

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
---gets set as a buffer variable `taggable_users`. If this list of users
---is needed synchronously, this function will need to be refactored.
---The list of taggable users should contain:
--  - The author of the issue/PR/discussion
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
  gh.api.get {
    "repos/{repo}/contributors",
    format = { repo = self.repo },
    jq = "map(.login)",
    opts = {
      cb = gh.create_callback {
        success = function(data)
          if utils.is_blank(data) then
            self.taggable_users = users
            return
          end

          ---@type string[]
          local contributors = vim.json.decode(data)
          for _, contributor in ipairs(contributors) do
            table.insert(users, contributor)
          end
          self.taggable_users = users
        end,
        failure = function() end,
      },
    },
  }
end

---Fetches the issues in the repo so they can be used for completion.
function OctoBuffer:async_fetch_issues()
  gh.api.get {
    "repos/{repo}/issues",
    format = { repo = self.repo },
    jq = "map({title, number})",
    opts = {
      cb = gh.create_callback {
        success = function(data)
          ---@type { number: integer, title: string }[]
          local issues_metadata = vim.json.decode(data)
          octo_repo_issues[self.repo] = issues_metadata
        end,
        failure = function() end,
      },
    },
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

    local input = { body = desc_metadata.body, title = title_metadata.body }

    local query, jq ---@type string, string
    if self:isIssue() then
      query = mutations.update_issue
      jq = ".data.updateIssue.issue"
      input["id"] = id
    elseif self:isPullRequest() then
      query = mutations.update_pull_request
      jq = ".data.updatePullRequest.pullRequest"
      input["pullRequestId"] = id
    elseif self:isDiscussion() then
      query = mutations.update_discussion
      jq = ".data.updateDiscussion.discussion"
      input["discussionId"] = id
    end

    gh.api.graphql {
      query = query,
      F = { input = input },
      jq = jq,
      opts = {
        cb = gh.create_callback {
          failure = utils.print_err,
          success = function(output)
            ---@type { title: string, body: string }
            local obj = vim.json.decode(output)

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
          end,
        },
      },
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
    ---@type octo.mutations.AddPullRequestReviewThreadInput
    local input = {
      pullRequestReviewId = comment_metadata.reviewId,
      body = comment_metadata.body,
      path = comment_metadata.path,
      side = comment_metadata.diffSide,
      line = comment_metadata.snippetStartLine,
    }

    if isMultiline then
      input["startLine"] = comment_metadata.snippetStartLine
      input["line"] = comment_metadata.snippetEndLine
    end

    gh.api.graphql {
      query = mutations.add_pull_request_review_thread,
      F = { input = input },
      opts = {
        cb = gh.create_callback {
          failure = utils.print_err,
          success = function(output)
            ---@type octo.mutations.AddPullRequestReviewThread
            local resp = vim.json.decode(output).data.addPullRequestReviewThread

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
          end,
        },
      },
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
    headers = { headers.json },
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

---Navigate to a specific comment by its databaseId
---@param opts { id: string, databaseId: integer }
function OctoBuffer:navigate_to_comment(opts)
  for _, comment in ipairs(self.commentsMetadata) do
    if comment.databaseId == opts.databaseId or comment.id == opts.id then
      local mark =
        vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, comment.extmark, { details = true })
      local start_line = mark[1] + 1
      vim.api.nvim_win_set_cursor(0, { start_line + 1, 0 })
      vim.cmd "normal! zz"
      return
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
