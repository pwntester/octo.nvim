--- Use source % to run this script
local gh = require "octo.gh"
local writers = require "octo.ui.writers"

---@type string
local now = "" .. os.date "!%Y-%m-%dT%H:%M:%SZ"

local me = gh.api.graphql { query = "query { viewer { login } }", jq = ".data.viewer.login", opts = { mode = "sync" } }
if me == nil then
  error "Failed to get viewer login"
end
local other = "octocat"

local id = "F_kwDOA8AAAW0b4h"

local repo = "pwntester/octo.nvim"
local branch = "main"

local bufnr = vim.api.nvim_get_current_buf()
local red = "#ff0000"
local green = "#00ff00"
local blue = "#0000ff"

---@type octo.fragments.Issue
local open_issue = {
  __typename = "Issue",
  id = id,
  number = 1,
  title = "Bug report",
  state = "OPEN",
  stateReason = nil,
}

---@type octo.fragments.Issue
local closed_issue = {
  __typename = "Issue",
  id = id,
  number = 1,
  title = "Bug report",
  state = "CLOSED",
  stateReason = "COMPLETED",
}

---@type octo.fragments.PullRequest
local pull_request = {
  __typename = "PullRequest",
  id = id,
  number = 2,
  title = "feat: Feature request",
  state = "MERGED",
  isDraft = false,
}

writers.write_timeline_items(bufnr, {
  timelineItems = {
    nodes = {
      ---@type octo.fragments.ReadyForReviewEvent
      {
        __typename = "ReadyForReviewEvent",
        actor = { login = me },
        createdAt = now,
      },
      ---@type octo.fragments.ConvertToDraftEvent
      {
        __typename = "ConvertToDraftEvent",
        actor = { login = other },
        createdAt = now,
      },
      ---@type octo.fragments.CrossReferencedEvent
      {
        __typename = "CrossReferencedEvent",
        actor = { login = other },
        createdAt = now,
        willCloseTarget = false,
        source = open_issue,
        target = open_issue,
      },
      ---@type octo.fragments.CrossReferencedEvent
      {
        __typename = "CrossReferencedEvent",
        actor = { login = other },
        createdAt = now,
        willCloseTarget = false,
        source = closed_issue,
        target = open_issue,
      },
      ---@type octo.fragments.CrossReferencedEvent
      {
        __typename = "CrossReferencedEvent",
        actor = { login = other },
        createdAt = now,
        willCloseTarget = false,
        source = pull_request,
        target = open_issue,
      },
      {
        __typename = "AddedToProjectV2Event",
        actor = { login = me },
        createdAt = now,
        project = { title = "Project 1" },
      },
      {
        __typename = "ProjectV2ItemStatusChangedEvent",
        actor = { login = other },
        createdAt = now,
        previousStatus = "",
        status = "To-Do",
        project = { title = "Project 1" },
      },
      {
        __typename = "ProjectV2ItemStatusChangedEvent",
        actor = { login = other },
        createdAt = now,
        previousStatus = "To-Do",
        status = "In Progress",
        project = { title = "Project 1" },
      },
      {
        __typename = "ProjectV2ItemStatusChangedEvent",
        actor = { login = other },
        createdAt = now,
        previousStatus = "In Progress",
        status = "",
        project = { title = "Project 1" },
      },
      {
        __typename = "RemovedFromProjectV2Event",
        actor = { login = me },
        createdAt = now,
        project = { title = "Project 1" },
      },
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "bug", color = red },
      },
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "enhancement", color = green },
      },
      ---@type octo.fragments.UnlabeledEvent
      {
        __typename = "UnlabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "enhancement", color = green },
      },
      ---@type octo.fragments.UnlabeledEvent
      {
        __typename = "UnlabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "bug", color = red },
      },
      {
        __typename = "CommentDeletedEvent",
        actor = { login = me },
        createdAt = now,
        deletedCommentAuthor = { login = me },
      },
      ---@type octo.fragments.CommentDeletedEvent
      {
        __typename = "CommentDeletedEvent",
        actor = { login = me },
        createdAt = now,
        deletedCommentAuthor = { login = other },
      },
      ---@type octo.fragments.AssignedEvent
      {
        __typename = "AssignedEvent",
        actor = { login = other },
        createdAt = now,
        assignee = { login = me },
      },
      ---@type octo.fragments.AssignedEvent
      {
        __typename = "AssignedEvent",
        actor = { login = other },
        createdAt = now,
        assignee = { login = other },
      },
      ---@type octo.fragments.AssignedEvent
      {
        __typename = "CommentDeletedEvent",
        actor = { login = other },
        createdAt = now,
        deletedCommentAuthor = { login = me },
      },
      ---@type octo.fragments.DeployedEvent
      {
        __typename = "DeployedEvent",
        createdAt = now,
        actor = { login = other },
        deployment = {
          environment = "production",
          state = "ACTIVE",
        },
      },
      ---@type octo.fragments.ReferencedEvent
      {
        __typename = "ReferencedEvent",
        createdAt = now,
        actor = { login = other },
        commit = {
          __typename = "Commit",
          abbreviatedOid = "abc1234",
          message = "Fix all the bugs",
          repository = {
            nameWithOwner = repo,
          },
        },
      },
      ---@type octo.fragments.AutoSquashEnabledEvent
      {
        __typename = "AutoSquashEnabledEvent",
        actor = { login = other },
        createdAt = now,
      },
      ---@type octo.fragments.HeadRefDeletedEvent
      {
        __typename = "HeadRefDeletedEvent",
        actor = { login = me },
        createdAt = now,
        headRefName = branch,
      },
      ---@type octo.fragments.HeadRefRestoredEvent
      {
        __typename = "HeadRefRestoredEvent",
        actor = { login = me },
        createdAt = now,
        pullRequest = { headRefName = branch },
      },
      ---@type octo.fragments.MergedEvent
      {
        __typename = "MergedEvent",
        actor = { login = other },
        createdAt = now,
        commit = { abbreviatedOid = "def5678" },
        mergeRefName = branch,
      },
      ---@type octo.fragments.PinnedEvent
      {
        __typename = "PinnedEvent",
        actor = { login = me },
        createdAt = now,
      },
      ---@type octo.fragments.UnpinnedEvent
      {
        __typename = "UnpinnedEvent",
        actor = { login = me },
        createdAt = now,
      },
    },
  },
})

---
--- Example timeline Below
---
