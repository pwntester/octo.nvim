--- Use source % to run this script and populate the current buffer
--- with example timeline items.
local gh = require "octo.gh"
local writers = require "octo.ui.writers"

local config = require("octo.config").values

config.use_timeline_icons = true

---@type string
local now = "" .. os.date "!%Y-%m-%dT%H:%M:%SZ"

local me = gh.api.graphql { query = "query { viewer { login } }", jq = ".data.viewer.login", opts = { mode = "sync" } }
if me == nil then
  error "Failed to get viewer login"
end
local other = "octocat"
local copilot_swe_agent = "copilot-swe-agent"

local id = "F_kwDOA8AAAW0b4h"

local repo = "pwntester/octo.nvim"
local another_repo = "octocat/octo.nvim"
local branch = "main"

local bufnr = vim.api.nvim_get_current_buf()
local red = "#ee0000"
local green = "#00af00"
local blue = "#0000ff"

local commit_message = "Fix all the bugs"
local large_commit_message = [[
This is a very large commit message that is intended to test how the timeline rendering handles large commit messages.

It should be displayed properly without any issues, and the text
should wrap correctly within the timeline item.
This commit message goes on and on to ensure that it exceeds typical lengths and
tests the robustness of the rendering logic in the octo.nvim plugin for Neovim.
Let's add some more text to make sure it's sufficiently large. Here we go, adding even more text to this commit message to push it further. Now we should be good!

]]

---@type octo.fragments.Issue
local open_issue = {
  __typename = "Issue",
  id = id,
  number = 1,
  title = "Bug report",
  state = "OPEN",
  stateReason = nil,
  repository = { nameWithOwner = repo },
}

---@type octo.fragments.PullRequestCommit
local example_commit = {
  __typename = "PullRequestCommit",
  commit = {
    abbreviatedOid = "45f511e",
    additions = 1,
    author = { user = { login = me } },
    changedFiles = 1,
    committedDate = "2025-12-05T14:41:52Z",
    committer = { user = { login = me } },
    deletions = 0,
    messageHeadline = "feat: add draft to PR buffer picker",
    oid = "45f511ecc4973828392c61958777f781b9e0df21",
    statusCheckRollup = {
      state = "SUCCESS",
    },
  },
}
---@type octo.fragments.Issue
local closed_issue = {
  __typename = "Issue",
  id = id,
  number = 2,
  title = "Another Bug report",
  state = "CLOSED",
  stateReason = "COMPLETED",
  repository = { nameWithOwner = repo },
}

---@type octo.fragments.PullRequest
local pull_request = {
  __typename = "PullRequest",
  id = id,
  number = 3,
  title = "feat: Feature request",
  state = "MERGED",
  isDraft = false,
  repository = { nameWithOwner = repo },
}

writers.write_timeline_items(bufnr, {
  timelineItems = {
    nodes = {
      --- Single commit event doesn't have summary
      example_commit,
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
        isCrossRepository = false,
        source = open_issue,
        target = open_issue,
      },
      ---@type octo.fragments.CrossReferencedEvent
      {
        __typename = "CrossReferencedEvent",
        actor = { login = other },
        createdAt = now,
        willCloseTarget = false,
        isCrossRepository = false,
        source = closed_issue,
        target = open_issue,
      },
      ---@type octo.fragments.CrossReferencedEvent
      {
        __typename = "CrossReferencedEvent",
        actor = { login = other },
        createdAt = now,
        willCloseTarget = false,
        isCrossRepository = false,
        source = pull_request,
        target = open_issue,
      },
      {
        __typename = "CrossReferencedEvent",
        actor = { login = other },
        createdAt = now,
        willCloseTarget = false,
        isCrossRepository = true,
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
      --- Various labeled and unlabeled events to test deduplication and combination
      ---@type octo.fragments.LabeledEvent
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "bug", color = red },
      },
      {
        __typename = "UnlabeledEvent",
        actor = { login = me },
        createdAt = now,
        label = { id = id, name = "bug", color = red },
      },
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "enhancement", color = green },
      },
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "tests", color = blue },
      },
      -- Duplicate labeled events (should be deduplicated)
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "enhancement", color = green },
      },
      {
        __typename = "LabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "tests", color = blue },
      },
      ---@type octo.fragments.UnlabeledEvent
      {
        __typename = "UnlabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "enhancement", color = green },
      },
      -- Duplicate unlabeled events (should be deduplicated)
      ---@type octo.fragments.UnlabeledEvent
      {
        __typename = "UnlabeledEvent",
        actor = { login = other },
        createdAt = now,
        label = { id = id, name = "enhancement", color = green },
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
          message = commit_message,
          repository = { nameWithOwner = repo },
        },
      },
      ---@type octo.fragments.AutoSquashEnabledEvent
      {
        __typename = "AutoSquashEnabledEvent",
        actor = { login = other },
        createdAt = now,
      },
      --- Two referenced events to test grouping
      ---@type octo.fragments.ReferencedEvent
      {
        __typename = "ReferencedEvent",
        createdAt = now,
        actor = { login = other },
        commit = {
          __typename = "Commit",
          abbreviatedOid = "abc1234",
          message = large_commit_message,
          repository = { nameWithOwner = repo },
        },
      },
      {
        __typename = "ReferencedEvent",
        createdAt = now,
        actor = { login = other },
        commit = {
          __typename = "Commit",
          abbreviatedOid = "abc1234",
          message = "Fix all the bugs",
          repository = { nameWithOwner = repo },
        },
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
      ---@type octo.fragments.ReviewRequestedEvent
      {
        __typename = "ReviewRequestedEvent",
        actor = { login = copilot_swe_agent },
        requestedReviewer = { login = me },
        createdAt = now,
      },
      {
        __typename = "ReviewRequestedEvent",
        actor = { login = copilot_swe_agent },
        requestedReviewer = { login = other },
        createdAt = now,
      },
      --- Sequence of commits have a summary
      example_commit,
      example_commit,
      example_commit,
      ---@type octo.fragments.TransferredEvent
      {
        __typename = "TransferredEvent",
        actor = { login = me },
        createdAt = now,
        fromRepository = { nameWithOwner = repo },
      },
    },
  },
})

---
--- Example timeline Below
---
