local CommentMetadata = require("octo.model.comment-metadata").CommentMetadata
local ThreadMetadata = require("octo.model.thread-metadata").ThreadMetadata
local BodyMetadata = require("octo.model.body-metadata").BodyMetadata
local TitleMetadata = require("octo.model.title-metadata").TitleMetadata
local constants = require "octo.constants"
local config = require "octo.config"
local utils = require "octo.utils"
local folds = require "octo.folds"
local bubbles = require "octo.ui.bubbles"
local vim = vim

local M = {}

function M.write_block(bufnr, lines, line, mark)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_buf_line_count(bufnr) + 1
  mark = mark or false

  if type(lines) == "string" then
    lines = vim.split(lines, "\n", true)
  end

  -- write content lines
  vim.api.nvim_buf_set_lines(bufnr, line - 1, line - 1 + #lines, false, lines)

  -- set extmarks
  if mark then
    -- (empty line) start ext mark at 0
    -- start line
    -- ...
    -- end line
    -- (empty line)
    -- (empty line) end ext mark at 0
    --
    -- (except for title where we cant place initial mark on line -1)

    local start_line = line
    local end_line = line
    local count = start_line + #lines
    for i = count, start_line, -1 do
      local text = vim.fn.getline(i) or ""
      if "" ~= text then
        end_line = i
        break
      end
    end

    return vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_COMMENT_NS, math.max(0, start_line - 1 - 1), 0, {
      end_line = math.min(end_line + 2 - 1, vim.api.nvim_buf_line_count(bufnr)),
      end_col = 0,
    })
  end
end

local function add_details_line(details, label, value, kind)
  if type(value) == "function" then
    value = value()
  end
  if value ~= vim.NIL and value ~= nil then
    if kind == "date" then
      value = utils.format_date(value)
    end
    local vt = { { label .. ": ", "OctoDetailsLabel" } }
    if kind == "label" then
      vim.list_extend(vt, bubbles.make_label_bubble(value.name, value.color, { right_margin_width = 1 }))
    elseif kind == "labels" then
      for _, v in ipairs(value) do
        if v ~= vim.NIL and v ~= nil then
          vim.list_extend(vt, bubbles.make_label_bubble(v.name, v.color, { right_margin_width = 1 }))
        end
      end
    else
      vim.list_extend(vt, { { tostring(value), "OctoDetailsValue" } })
    end
    table.insert(details, vt)
  end
end

function M.write_discussion_details(bufnr, discussion)
  local details = {}

  -- clear namespace and set vt
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, 0, -1)

  local author_vt = { { "Created by: ", "OctoDetailsLabel" } }
  local author_bubble = bubbles.make_user_bubble(discussion.author.login, discussion.viewerDidAuthor)
  vim.list_extend(author_vt, author_bubble)
  table.insert(details, author_vt)

  local category_vt = {
    { "Category: ", "OctoDetailsLabel" },
    { discussion.category.name, "OctoDetailsValue" },
  }
  table.insert(details, category_vt)

  add_details_line(details, "Created at", discussion.createdAt, "date")
  add_details_line(details, "Updated at", discussion.updatedAt, "date")

  local labels_vt = { { "Labels: ", "OctoDetailsLabel" } }

  if #discussion.labels.nodes > 0 then
    for _, label in ipairs(discussion.labels.nodes) do
      local label_bubble = bubbles.make_label_bubble(label.name, label.color, { right_margin_width = 1 })
      vim.list_extend(labels_vt, label_bubble)
    end
  else
    table.insert(labels_vt, { "None yet", "OctoMissingDetails" })
  end

  table.insert(details, labels_vt)

  -- Is answered details
  local answered_vt = {
    { "Answered: ", "OctoDetailsLabel" },
  }
  if discussion.isAnswered ~= vim.NIL and discussion.isAnswered then
    table.insert(answered_vt, { "Yes", "OctoGreen" })
  else
    table.insert(answered_vt, { "Not yet", "OctoMissingDetails" })
  end
  table.insert(details, answered_vt)

  add_details_line(details, "Comments", discussion.comments.totalCount)

  M.write_detail_table { bufnr = bufnr, details = details, offset = 3 }
end

function M.write_detail_table(opts)
  local bufnr = opts.bufnr
  local details = opts.details
  local line = opts.offset

  local empty_lines = {}
  for _ = 1, #details + 1 do
    table.insert(empty_lines, "")
  end
  M.write_block(bufnr, empty_lines, line)
  for _, d in ipairs(details) do
    M.write_virtual_text(bufnr, constants.OCTO_REPO_VT_NS, line - 1, d)
    line = line + 1
  end
end

function M.write_upvotes(bufnr, obj, line)
  -- clear namespace and set vt
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)

  local upvote_symbol = " "

  local upvotes = obj.upvoteCount
  local viewer_did_upvote = obj.viewerHasUpvoted

  local upvotes_vt = {
    { upvote_symbol, "OctoDetailsLabel" },
    { " " .. upvotes, "OctoDetailsValue" },
  }
  M.write_block(bufnr, { "" }, line)
  M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line, upvotes_vt)
end

function M.write_discussion_answer(bufnr, obj, line)
  local answer = obj.answer

  local answer_vt = {
    { "Answered by: ", "OctoDetailsLabel" },
  }
  local author_bubble = bubbles.make_user_bubble(answer.author.login, answer.viewerDidAuthor)
  vim.list_extend(answer_vt, author_bubble)
  table.insert(answer_vt, { " " .. utils.format_date(answer.createdAt), "OctoDetailsValue" })

  M.write_detail_table { bufnr = bufnr, details = { answer_vt }, offset = line }

  line = line + 10
  M.write_block(bufnr, answer.body:gsub("\r\n", "\n"), line)
end

function M.write_repo(bufnr, repo)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local details = {}

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REPO_VT_NS, 0, -1)

  add_details_line(details, "Name", repo.nameWithOwner)
  add_details_line(details, "Description", repo.description)
  local defaultBranchRefName
  if repo.defaultBranchRef == vim.NIL then
    defaultBranchRefName = nil
  else
    defaultBranchRefName = repo.defaultBranchRef.name
  end
  add_details_line(details, "Default branch", defaultBranchRefName)
  add_details_line(details, "URL", repo.url)
  add_details_line(details, "Homepage URL", function()
    if not utils.is_blank(repo.homepageUrl) then
      return repo.homepageUrl
    else
      return nil
    end
  end)
  add_details_line(details, "Stars", repo.stargazerCount)
  add_details_line(details, "Forks", repo.forkCount)
  add_details_line(details, "Size", repo.diskUsage)
  add_details_line(details, "Created at", repo.createdAt, "date")
  add_details_line(details, "Updated at", repo.updatedAt, "date")
  add_details_line(details, "Pushed at", repo.pushedAt, "date")
  add_details_line(details, "Forked from", function()
    if repo.isFork and repo.parent ~= vim.NIL then
      return repo.parent.nameWithOwner
    else
      return nil
    end
  end)
  add_details_line(details, "Archived", repo.isArchived, "boolean")
  add_details_line(details, "Disabled", repo.isDisabled, "boolean")
  add_details_line(details, "Empty", repo.isEmpty, "boolean")
  add_details_line(details, "Private", repo.isPrivate, "boolean")
  add_details_line(details, "Belongs to Org", repo.isInOrganization, "boolean")
  add_details_line(details, "Locked", function()
    if repo.isLocked == "true" and utils.is_blank(repo.lockReason) then
      return repo.lockReason
    else
      return nil
    end
  end)
  add_details_line(details, "Mirrored from", function()
    if repo.isMirror == "true" then
      return repo.mirrorUrl
    else
      return nil
    end
  end)
  add_details_line(details, "Security Policy", function()
    if repo.isSecurityPolicyEnabled == "true" then
      return repo.securityPolicyUrl
    else
      return nil
    end
  end)
  add_details_line(details, "Projects URL", function()
    if repo.hasProjectsEnabled == "true" then
      return repo.projectsUrl
    else
      return nil
    end
  end)
  add_details_line(details, "Primary language", repo.primaryLanguage, "label")
  add_details_line(details, "Languages", repo.languages.nodes, "labels")

  -- write #details + empty lines
  local line = 1
  local empty_lines = {}
  for _ = 1, #details + 1 do
    table.insert(empty_lines, "")
  end
  M.write_block(bufnr, empty_lines, line)
  for _, d in ipairs(details) do
    M.write_virtual_text(bufnr, constants.OCTO_REPO_VT_NS, line - 1, d)
    line = line + 1
  end

  if defaultBranchRefName ~= nil then
    utils.get_file_contents(repo.nameWithOwner, defaultBranchRefName, "README.md", function(lines)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
        vim.api.nvim_buf_set_option(bufnr, "modified", false)
      end
    end)
  end
end

function M.write_title(bufnr, title, line)
  local title_mark = M.write_block(bufnr, { title, "" }, line, true)
  vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoIssueTitle", 0, 0, -1)
  local buffer = octo_buffers[bufnr]

  if buffer then
    buffer.titleMetadata = TitleMetadata:new {
      savedBody = title,
      body = title,
      dirty = false,
      extmark = tonumber(title_mark),
    }
  end
end

function M.write_state(bufnr, state, number)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  state = state or buffer.node.state
  number = number or buffer.number

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_TITLE_VT_NS, 0, -1)

  -- title virtual text
  local title_vt = {
    { tostring(number), "OctoIssueId" },
    { string.format(" [%s] ", state:gsub("_", " ")), utils.state_hl_map[state] },
  }

  -- PR virtual text
  if buffer and buffer:isPullRequest() then
    if buffer.node.isDraft then
      table.insert(title_vt, { "[DRAFT] ", "OctoStateDraftFloat" })
    end
  end
  vim.api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_TITLE_VT_NS, 0, title_vt, {})
end

function M.write_body(bufnr, issue, line)
  local body = utils.trim(issue.body)
  if vim.startswith(body, constants.NO_BODY_MSG) or utils.is_blank(body) then
    body = " "
  end
  local description = body:gsub("\r\n", "\n")
  local lines = vim.split(description, "\n", true)
  vim.list_extend(lines, { "" })
  local desc_mark = M.write_block(bufnr, lines, line, true)
  local buffer = octo_buffers[bufnr]
  if buffer then
    buffer.bodyMetadata = BodyMetadata:new {
      savedBody = description,
      body = description,
      dirty = false,
      extmark = desc_mark,
      viewerCanUpdate = issue.viewerCanUpdate,
    }
  end
end

function M.write_reactions(bufnr, reaction_groups, line)
  local reactions_count = utils.count_reactions(reaction_groups)
  if reactions_count <= 0 then
    return nil
  end

  -- clear namespace and set vt
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)

  local reactions_vt = {}
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      local icon = utils.reaction_map[group.content]
      local bubble = bubbles.make_reaction_bubble(icon, group.viewerHasReacted)
      vim.list_extend(reactions_vt, bubble)
      table.insert(reactions_vt, { " " .. group.users.totalCount .. " ", "NormalFront" })
    end
  end
  M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, reactions_vt)
  return line
end

function M.write_details(bufnr, issue, update)
  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DETAILS_VT_NS, 0, -1)

  local details = {}
  local buffer = octo_buffers[bufnr]

  -- repo
  local repo_vt = {
    { "Repo: ", "OctoDetailsLabel" },
    { " " .. utils.parse_url(issue.url), "OctoDetailsValue" },
  }
  table.insert(details, repo_vt)

  -- author
  local author_vt = { { "Created by: ", "OctoDetailsLabel" } }
  local opts = {}
  if utils.is_blank(issue.author) then
    issue.author = { login = "ghost" }
    opts = { ghost = true }
  end
  local author_bubble = bubbles.make_user_bubble(issue.author.login, issue.viewerDidAuthor, opts)

  vim.list_extend(author_vt, author_bubble)
  table.insert(details, author_vt)

  add_details_line(details, "Created", issue.createdAt, "date")
  if issue.state == "CLOSED" then
    add_details_line(details, "Closed", issue.closedAt, "date")
  else
    add_details_line(details, "Updated", issue.updatedAt, "date")
  end

  -- assignees
  local assignees_vt = {
    { "Assignees: ", "OctoDetailsLabel" },
  }
  if issue.assignees and #issue.assignees.nodes > 0 then
    for _, assignee in ipairs(issue.assignees.nodes) do
      local user_bubble = bubbles.make_user_bubble(assignee.login, assignee.isViewer, { margin_width = 1 })
      vim.list_extend(assignees_vt, user_bubble)
    end
  else
    table.insert(assignees_vt, { "No one assigned ", "OctoMissingDetails" })
  end
  table.insert(details, assignees_vt)

  -- projects
  if issue.projectCards and #issue.projectCards.nodes > 0 then
    local projects_vt = {
      { "Projects: ", "OctoDetailsLabel" },
    }
    --local project_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("NormalFloat")), "bg#"):sub(2)
    --local column_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("Comment")), "fg#"):sub(2)
    for _, card in ipairs(issue.projectCards.nodes) do
      if card.column ~= vim.NIL then
        table.insert(projects_vt, { card.column.name })
        if not utils.is_blank(card.project) then
          table.insert(projects_vt, { " (", "OctoDetailsLabel" })
          table.insert(projects_vt, { card.project.name })
          table.insert(projects_vt, { ")", "OctoDetailsLabel" })
        end
      end
    end
    table.insert(details, projects_vt)
  end

  -- projects v2
  if issue.projectItems and #issue.projectItems.nodes > 0 then
    local projects_vt = {
      { "Projects (v2): ", "OctoDetailsLabel" },
    }
    --local project_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("NormalFloat")), "bg#"):sub(2)
    --local column_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("Comment")), "fg#"):sub(2)
    for idx, item in ipairs(issue.projectItems.nodes) do
      if item.project ~= vim.NIL then
        if idx >= 2 then
          table.insert(projects_vt, { ", " })
        end

        local status = nil

        for _, fieldValues in ipairs(item.fieldValues.nodes) do
          if fieldValues.field ~= nil and fieldValues.field.name == "Status" then
            status = fieldValues.name
          end
        end

        if status == nil then
          table.insert(projects_vt, { "No status", "OctoRed" })
        else
          table.insert(projects_vt, { status })
        end

        table.insert(projects_vt, { " (", "OctoDetailsLabel" })
        table.insert(projects_vt, { item.project.title })
        table.insert(projects_vt, { ")", "OctoDetailsLabel" })
      end
    end
    table.insert(details, projects_vt)
  end

  -- milestones
  local ms = issue.milestone
  local milestone_vt = {
    { "Milestone: ", "OctoDetailsLabel" },
  }
  if ms ~= nil and ms ~= vim.NIL then
    table.insert(milestone_vt, { ms.title, "OctoDetailsValue" })
    table.insert(milestone_vt, { string.format(" (%s)", utils.state_message_map[ms.state]), "OctoDetailsValue" })
  else
    table.insert(milestone_vt, { "No milestone", "OctoMissingDetails" })
  end
  table.insert(details, milestone_vt)

  -- labels
  local labels_vt = {
    { "Labels: ", "OctoDetailsLabel" },
  }
  if #issue.labels.nodes > 0 then
    for _, label in ipairs(issue.labels.nodes) do
      local label_bubble = bubbles.make_label_bubble(label.name, label.color, { right_margin_width = 1 })
      vim.list_extend(labels_vt, label_bubble)
    end
  else
    table.insert(labels_vt, { "None yet", "OctoMissingDetails" })
  end
  table.insert(details, labels_vt)

  -- additional details for pull requests
  if issue.commits then
    -- reviewers
    local reviewers = {}
    local collect_reviewer = function(name, state)
      if not reviewers[name] then
        reviewers[name] = { state }
      else
        local states = reviewers[name]
        if not vim.tbl_contains(states, state) then
          table.insert(states, state)
        end
        reviewers[name] = states
      end
    end
    local timeline_nodes = {}
    for _, item in ipairs(issue.timelineItems.nodes) do
      if item ~= vim.NIL then
        table.insert(timeline_nodes, item)
      end
    end
    for _, item in ipairs(timeline_nodes) do
      if item.__typename == "PullRequestReview" then
        local name = item.author.login
        collect_reviewer(name, item.state)
      end
    end
    if issue.reviewRequests and issue.reviewRequests.totalCount > 0 then
      for _, reviewRequest in ipairs(issue.reviewRequests.nodes) do
        if reviewRequest.requestedReviewer ~= vim.NIL then
          local name = reviewRequest.requestedReviewer.login or reviewRequest.requestedReviewer.name
          collect_reviewer(name, "REVIEW_REQUIRED")
        end
      end
    end
    local reviewers_vt = {
      { "Reviewers: ", "OctoDetailsLabel" },
    }
    if #vim.tbl_keys(reviewers) > 0 then
      for _, name in ipairs(vim.tbl_keys(reviewers)) do
        local strongest_review = utils.calculate_strongest_review_state(reviewers[name])
        local reviewer_vt = {
          { name, "OctoUser" },
          { utils.state_icon_map[strongest_review], utils.state_hl_map[strongest_review] },
          { " " },
        }
        vim.list_extend(reviewers_vt, reviewer_vt)
      end
    else
      table.insert(reviewers_vt, { "No reviewers", "OctoMissingDetails" })
    end
    table.insert(details, reviewers_vt)

    -- merged_by
    if issue.merged then
      local merged_by_vt = { { "Merged by: ", "OctoDetailsLabel" } }
      local name = issue.mergedBy.login or issue.mergedBy.name
      local is_viewer = issue.mergedBy.isViewer or false
      local user_bubble = bubbles.make_user_bubble(name, is_viewer)
      vim.list_extend(merged_by_vt, user_bubble)
      table.insert(details, merged_by_vt)
    end

    -- from/into branches
    local branches_vt = {
      { "From: ", "OctoDetailsLabel" },
      { issue.headRefName, "OctoDetailsValue" },
      { " Into: ", "OctoDetailsLabel" },
      { issue.baseRefName, "OctoDetailsValue" },
    }
    table.insert(details, branches_vt)

    -- review decision
    if issue.reviewDecision and issue.reviewDecision ~= vim.NIL then
      local decision_vt = {
        { "Review decision: ", "OctoDetailsLabel" },
        { utils.state_message_map[issue.reviewDecision] },
      }
      table.insert(details, decision_vt)
    end

    -- checks
    if issue.statusCheckRollup and issue.statusCheckRollup ~= vim.NIL then
      local state = issue.statusCheckRollup.state
      local state_info = utils.state_map[state]
      local message = state_info.symbol .. state
      local checks_vt = {
        { "Checks: ", "OctoDetailsLabel" },
        { message, state_info.hl },
      }
      table.insert(details, checks_vt)
    end

    -- merge state
    if not issue.merged and issue.mergeable then
      local merge_state_vt = {
        { "Merge: ", "OctoDetailsLabel" },
      }

      if issue.mergeable == "MERGEABLE" then
        table.insert(
          merge_state_vt,
          { utils.merge_state_message_map[issue.mergeStateStatus], utils.merge_state_hl_map[issue.mergeStateStatus] }
        )
      else
        table.insert(
          merge_state_vt,
          { utils.mergeable_message_map[issue.mergeable], utils.mergeable_hl_map[issue.mergeable] }
        )
      end

      table.insert(details, merge_state_vt)
    end

    if not issue.merged and issue.autoMergeRequest and issue.autoMergeRequest ~= vim.NIL then
      local auto_merge_vt = {
        { "Auto-merge: ", "OctoDetailsLabel" },
        { "ENABLED", "OctoStateApproved" },
        { " by " },
        { issue.autoMergeRequest.enabledBy.login, "OctoUser" },
        { " (" .. utils.auto_merge_method_map[issue.autoMergeRequest.mergeMethod] .. ")" },
      }
      table.insert(details, auto_merge_vt)
    end

    -- changes
    local changes_vt = {
      { "Commits: ", "OctoDetailsLabel" },
      { tostring(issue.commits.totalCount), "OctoDetailsValue" },
      { " Changed files: ", "OctoDetailsLabel" },
      { tostring(issue.changedFiles), "OctoDetailsValue" },
      { " (", "OctoDetailsLabel" },
      { string.format("+%d ", issue.additions), "OctoDiffstatAdditions" },
      { string.format("-%d ", issue.deletions), "OctoDiffstatDeletions" },
    }
    local diffstat = utils.diffstat { additions = issue.additions, deletions = issue.deletions }
    if diffstat.additions > 0 then
      table.insert(changes_vt, { string.rep("■", diffstat.additions), "OctoDiffstatAdditions" })
    end
    if diffstat.deletions > 0 then
      table.insert(changes_vt, { string.rep("■", diffstat.deletions), "OctoDiffstatDeletions" })
    end
    if diffstat.neutral > 0 then
      table.insert(changes_vt, { string.rep("■", diffstat.neutral), "OctoDiffstatNeutral" })
    end
    table.insert(changes_vt, { ")", "OctoDetailsLabel" })
    table.insert(details, changes_vt)
  end

  local line = 3
  -- write #details + empty lines
  local empty_lines = {}
  for _ = 1, #details + 1 do
    table.insert(empty_lines, "")
  end
  if not update then
    M.write_block(bufnr, empty_lines, line)
  end

  -- write details as virtual text
  for _, d in ipairs(details) do
    M.write_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line - 1, d)
    line = line + 1
  end
end

function M.write_comment(bufnr, comment, kind, line)
  -- possible kinds:
  ---- IssueComment
  ---- PullRequestReview
  ---- PullRequestReviewComment
  ---- PullRequestComment (regular comment (not associated to any review) to a PR review comment)

  local buffer = octo_buffers[bufnr]
  local conf = config.values

  -- heading
  line = line or vim.api.nvim_buf_line_count(bufnr) + 1
  local start_line = line
  M.write_block(bufnr, { "", "" }, line)

  local header_vt = {}
  -- local author_bubble = bubbles.make_user_bubble(
  --   comment.author.login,
  --   comment.viewerDidAuthor,
  --   { margin_width = 1 }
  -- )

  if kind == "PullRequestReview" then
    -- Review top-level comments
    local state_bubble =
      bubbles.make_bubble(utils.state_msg_map[comment.state], utils.state_hl_map[comment.state] .. "Bubble")
    table.insert(header_vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
    table.insert(header_vt, { "REVIEW: ", "OctoTimelineItemHeading" })
    --vim.list_extend(header_vt, author_bubble)
    table.insert(header_vt, {
      comment.author.login,
      comment.viewerDidAuthor and "OctoUserViewer" or "OctoUser",
    })
    table.insert(header_vt, { " ", "OctoTimelineItemHeading" })
    vim.list_extend(header_vt, state_bubble)
    table.insert(header_vt, { " " .. utils.format_date(comment.createdAt), "OctoDate" })
    if not comment.viewerCanUpdate then
      table.insert(header_vt, { " ", "OctoRed" })
    end
  elseif kind == "PullRequestReviewComment" then
    -- Review thread comments
    local state_bubble =
      bubbles.make_bubble(comment.state:lower(), utils.state_hl_map[comment.state] .. "Bubble", { margin_width = 1 })
    table.insert(
      header_vt,
      { string.rep(" ", 2 * conf.timeline_indent) .. conf.timeline_marker .. " ", "OctoTimelineMarker" }
    )
    table.insert(header_vt, { "THREAD COMMENT: ", "OctoTimelineItemHeading" })
    table.insert(header_vt, { comment.author.login, comment.viewerDidAuthor and "OctoUserViewer" or "OctoUser" })
    if comment.state ~= "SUBMITTED" then
      vim.list_extend(header_vt, state_bubble)
    end
    table.insert(header_vt, { " " .. utils.format_date(comment.createdAt), "OctoDate" })
    if not comment.viewerCanUpdate then
      table.insert(header_vt, { " ", "OctoRed" })
    end
  elseif kind == "PullRequestComment" then
    -- Regular comment for a review thread comments
    table.insert(
      header_vt,
      { string.rep(" ", 2 * conf.timeline_indent) .. conf.timeline_marker .. " ", "OctoTimelineMarker" }
    )
    table.insert(header_vt, { "COMMENT: ", "OctoTimelineItemHeading" })
    table.insert(header_vt, { comment.author.login, comment.viewerDidAuthor and "OctoUserViewer" or "OctoUser" })
    table.insert(header_vt, { " " .. utils.format_date(comment.createdAt), "OctoDate" })
    if not comment.viewerCanUpdate then
      table.insert(header_vt, { " ", "OctoRed" })
    end
  elseif kind == "IssueComment" then
    -- Issue comments
    table.insert(header_vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
    table.insert(header_vt, { "COMMENT: ", "OctoTimelineItemHeading" })
    --vim.list_extend(header_vt, author_bubble)
    if comment.author ~= vim.NIL then
      table.insert(header_vt, { comment.author.login, comment.viewerDidAuthor and "OctoUserViewer" or "OctoUser" })
    end
    table.insert(header_vt, { " " .. utils.format_date(comment.createdAt), "OctoDate" })
    if not comment.viewerCanUpdate then
      table.insert(header_vt, { " ", "OctoRed" })
    end
  end
  local comment_vt_ns = vim.api.nvim_create_namespace ""
  M.write_virtual_text(bufnr, comment_vt_ns, line - 1, header_vt)

  if kind == "PullRequestReview" and utils.is_blank(comment.body) then
    -- do not render empty review comments
    return start_line, start_line + 1
  end

  -- body
  line = line + 2
  local comment_body = utils.trim(string.gsub(comment.body, "\r\n", "\n"))
  if vim.startswith(comment_body, constants.NO_BODY_MSG) or utils.is_blank(comment_body) then
    comment_body = " "
  end
  local content = vim.split(comment_body, "\n", true)
  vim.list_extend(content, { "" })
  local comment_mark = M.write_block(bufnr, content, line, true)

  line = line + #content

  -- reactions
  local reaction_line
  if utils.count_reactions(comment.reactionGroups) > 0 then
    M.write_block(bufnr, { "", "" }, line)
    reaction_line = M.write_reactions(bufnr, comment.reactionGroups, line)
    line = line + 2
  end

  -- update metadata
  local comments_metadata = buffer.commentsMetadata
  table.insert(
    comments_metadata,
    CommentMetadata:new {
      author = comment.author ~= vim.NIL and comment.author.name or "",
      id = comment.id,
      dirty = false,
      savedBody = comment_body,
      body = comment_body,
      extmark = comment_mark,
      namespace = comment_vt_ns,
      reactionLine = reaction_line,
      viewerCanUpdate = comment.viewerCanUpdate,
      viewerCanDelete = comment.viewerCanDelete,
      viewerDidAuthor = comment.viewerDidAuthor,
      reactionGroups = comment.reactionGroups,
      kind = kind,
      replyTo = comment.replyTo,
      replyToRest = comment.replyToRest,
      reviewId = comment.pullRequestReview and comment.pullRequestReview.id,
      path = comment.path,
      diffSide = comment.diffSide,
      snippetStartLine = comment.start_line,
      snippetEndLine = comment.end_line,
    }
  )

  return start_line, line - 1
end

local function find_snippet_range(diffhunk_lines)
  local conf = config.values
  local context_lines = conf.snippet_context_lines or 4
  local snippet_start
  local count = 0
  for i = #diffhunk_lines, 1, -1 do
    local line = diffhunk_lines[i]

    -- once we find where the snippet should start, add `context_lines` of context
    if snippet_start then
      if vim.startswith(line, "+") or vim.startswith(line, "-") then
        -- we found a different diff, so do not include it
        snippet_start = i + 1
        break
      end
      snippet_start = i
      count = count + 1
      if count > context_lines then
        break
      end
    end

    -- if we cant find a lower boundary in the last `context_lines` then set boundary
    if not snippet_start and i < #diffhunk_lines - context_lines + 2 then
      snippet_start = i
      break
    end

    -- found lower boundary
    if not snippet_start and not vim.startswith(line, "+") and not vim.startswith(line, "-") then
      snippet_start = i
    end
  end

  local snippet_end = #diffhunk_lines

  return snippet_start, snippet_end
end

local function get_lnum_chunks(opts)
  if not opts.left_line and opts.right_line then
    return {
      { string.rep(" ", opts.max_lnum), "DiffAdd" },
      { " ", "DiffAdd" },
      {
        string.rep(" ", opts.max_lnum - vim.fn.strdisplaywidth(tostring(opts.right_line))) .. tostring(opts.right_line),
        "DiffAdd",
      },
      { " ", "DiffAdd" },
    }
  elseif not opts.right_line and opts.left_line then
    return {
      {
        string.rep(" ", opts.max_lnum - vim.fn.strdisplaywidth(tostring(opts.left_line))) .. tostring(opts.left_line),
        "DiffDelete",
      },
      { " ", "DiffDelete" },
      { string.rep(" ", opts.max_lnum), "DiffDelete" },
      { " ", "DiffDelete" },
    }
  elseif opts.right_line and opts.left_line then
    return {
      {
        string.rep(" ", opts.max_lnum - vim.fn.strdisplaywidth(tostring(opts.left_line))) .. tostring(opts.left_line),
      },
      { " " },
      {
        string.rep(" ", opts.max_lnum - vim.fn.strdisplaywidth(tostring(opts.right_line))) .. tostring(opts.right_line),
      },
      { " " },
    }
  end
end

function M.write_thread_snippet(bufnr, diffhunk, start_line, comment_start, comment_end, comment_side)
  -- this function will print a diff snippet from the diff hunk.
  -- we need to use the original positions for comment_start and comment_end
  -- since the diff hunk always use the original positions.

  start_line = start_line or vim.api.nvim_buf_line_count(bufnr) + 1
  if not diffhunk then
    return start_line, start_line
  end

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DIFFHUNK_VT_NS, start_line - 2, -1)

  -- generate maps from diffhunk line to code line:
  local diffhunk_lines = vim.split(diffhunk, "\n")
  local map = utils.generate_position2line_map(diffhunk)

  -- calculate length of the higher line number
  local max_lnum = math.max(
    vim.fn.strdisplaywidth(tostring(map.right_offset + #diffhunk_lines)),
    vim.fn.strdisplaywidth(tostring(map.left_offset + #diffhunk_lines))
  )

  -- calculate diffhunk subrange to show
  local side_lines
  if comment_side == "RIGHT" then
    side_lines = map.right_side_lines
  elseif comment_side == "LEFT" then
    side_lines = map.left_side_lines
  end
  local snippet_start, snippet_end
  if comment_side and comment_start ~= comment_end then
    -- multiline comment: write just those lines
    for pos, l in pairs(side_lines) do
      if tonumber(l) == tonumber(comment_start) then
        snippet_start = pos
      elseif tonumber(l) == tonumber(comment_end) then
        snippet_end = pos
      end
    end
  else
    -- for single-line comment, add additional context lines
    for pos, l in pairs(side_lines) do
      if tonumber(l) == tonumber(comment_start) then
        snippet_start, snippet_end = find_snippet_range(utils.tbl_slice(diffhunk_lines, 1, pos, 1))
        break
      end
    end
  end
  if not snippet_end then
    -- could not find comment end line in the diff hunk,
    -- defaulting to last diff hunk line
    snippet_end = #side_lines
  end
  if not snippet_start then
    -- could not find comment sart line in the diff hunk,
    -- defaulting to last diff hunk line - 3
    snippet_start = #side_lines - 3
  end

  -- calculate longest line in the visible section of the diffhunk
  local max_length = -1
  for i = snippet_start, snippet_end do
    local line = diffhunk_lines[i]
    if vim.fn.strdisplaywidth(line) > max_length then
      max_length = vim.fn.strdisplaywidth(line)
    end
  end
  max_length = math.max(max_length, vim.fn.winwidth(0) - 10)

  -- write empty lines to hold virtual text
  local empty_lines = {}
  for _ = snippet_start, snippet_end + 3 do
    table.insert(empty_lines, "")
  end
  M.write_block(bufnr, empty_lines, start_line)

  -- prepare vt chunks
  local vt_lines = {}
  table.insert(vt_lines, { { string.format("┌%s┐", string.rep("─", max_length + 2)) } })
  for i = snippet_start, snippet_end do
    local line = diffhunk_lines[i]
    if not line then
      break
    end

    if vim.startswith(line, "@@ ") then
      local index = string.find(line, "@[^@]*$")
      table.insert(vt_lines, {
        { "│" },
        { string.rep(" ", 2 * max_lnum + 1), "DiffLine" },
        { string.sub(line, 0, index), "DiffLine" },
        { string.sub(line, index + 1), "DiffLine" },
        { string.rep(" ", 1 + max_length - vim.fn.strdisplaywidth(line) - 2 * max_lnum), "DiffLine" },
        { "│" },
      })
    elseif vim.startswith(line, "+") then
      local vt_line = { { "│" } }
      vim.list_extend(vt_line, get_lnum_chunks { right_line = map.right_side_lines[i], max_lnum = max_lnum })
      vim.list_extend(vt_line, {
        { line:gsub("^.", " "), "DiffAdd" },
        { string.rep(" ", max_length - vim.fn.strdisplaywidth(line) - 2 * max_lnum), "DiffAdd" },
        { "│" },
      })
      table.insert(vt_lines, vt_line)
    elseif vim.startswith(line, "-") then
      local vt_line = { { "│" } }
      vim.list_extend(vt_line, get_lnum_chunks { left_line = map.left_side_lines[i], max_lnum = max_lnum })
      vim.list_extend(vt_line, {
        { line:gsub("^.", " "), "DiffDelete" },
        { string.rep(" ", max_length - vim.fn.strdisplaywidth(line) - 2 * max_lnum), "DiffDelete" },
        { "│" },
      })
      table.insert(vt_lines, vt_line)
    else
      local vt_line = { { "│" } }
      vim.list_extend(
        vt_line,
        get_lnum_chunks {
          left_line = map.left_side_lines[i],
          right_line = map.right_side_lines[i],
          max_lnum = max_lnum,
        }
      )
      vim.list_extend(vt_line, {
        { line },
        { string.rep(" ", max_length - vim.fn.strdisplaywidth(line) - 2 * max_lnum) },
        { "│" },
      })
      table.insert(vt_lines, vt_line)
    end
  end
  table.insert(vt_lines, { { string.format("└%s┘", string.rep("─", max_length + 2)) } })

  -- write snippet as virtual text
  local line = start_line - 1
  for _, vt_line in ipairs(vt_lines) do
    M.write_virtual_text(bufnr, constants.OCTO_DIFFHUNK_VT_NS, line, vt_line)
    line = line + 1
  end

  return start_line, line
end

function M.write_review_thread_header(bufnr, opts, line)
  line = line or vim.api.nvim_buf_line_count(bufnr) - 1

  local conf = config.values

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_THREAD_HEADER_VT_NS, line, line + 2)

  local header_vt = {
    { string.rep(" ", conf.timeline_indent) .. conf.timeline_marker .. " ", "OctoTimelineMarker" },
    { "THREAD: ", "OctoTimelineItemHeading" },
    { "[", "OctoSymbol" },
    { opts.path .. " ", "OctoDetailsLabel" },
    { tostring(opts.start_line) .. ":" .. tostring(opts.end_line), "OctoDetailsValue" },
    { "] [Commit: ", "OctoSymbol" },
    { opts.commit, "OctoDetailsLabel" },
    { "] ", "OctoSymbol" },
  }
  if opts.isOutdated then
    -- local outdated_bubble = bubbles.make_bubble(
    --   "outdate",
    --   "OctoBubbleRed",
    --   { margin_width = 1 }
    -- )
    -- vim.list_extend(header_vt, outdated_bubble)
    vim.list_extend(header_vt, { { conf.outdated_icon, "OctoRed" } })
  end

  if opts.isResolved then
    -- local resolved_bubble = bubbles.make_bubble(
    --   "resolved",
    --   "OctoBubbleGreen",
    --   { margin_width = 1 }
    -- )
    --vim.list_extend(header_vt, resolved_bubble)
    vim.list_extend(header_vt, { { conf.resolved_icon, "OctoGreen" } })
    if opts.resolvedBy then
      vim.list_extend(
        header_vt,
        { { " [Resolved by: ", "OctoSymbol" }, { opts.resolvedBy.login, "OctoDetailsLabel" }, { "] ", "OctoSymbol" } }
      )
    end
  end

  M.write_block(bufnr, { "" })
  M.write_virtual_text(bufnr, constants.OCTO_THREAD_HEADER_VT_NS, line + 1, header_vt)
end

function M.write_reactions_summary(bufnr, reactions)
  local lines = {}
  local max_width = math.floor(vim.fn.winwidth(0) * 0.4)
  for reaction, users in pairs(reactions) do
    local user_str = table.concat(users, ", ")
    local reaction_lines = utils.text_wrap(string.format(" %s %s", utils.reaction_map[reaction], user_str), max_width)
    local indented_lines = { reaction_lines[1] }
    for i = 2, #reaction_lines do
      table.insert(indented_lines, "   " .. reaction_lines[i])
    end
    vim.list_extend(lines, indented_lines)
  end
  local max_length = -1
  for _, line in ipairs(lines) do
    max_length = math.max(max_length, vim.fn.strdisplaywidth(line))
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, lines)
  return #lines, max_length
end

local function chunk_length(max_length, chunk)
  local length = 0
  for _, c in ipairs(chunk) do
    length = length + vim.fn.strdisplaywidth(c[1])
  end
  return math.max(max_length, length)
end

function M.write_user_profile(bufnr, user, opts)
  opts = opts or {}
  local max_width = opts.max_width or 80
  local chunks = {}
  local max_length = -1

  -- name
  local name_chunk = {
    { " " },
    { user.login, "OctoDetailsValue" },
  }
  if user.name ~= vim.NIL then
    vim.list_extend(name_chunk, {
      { string.format(" (%s)", user.name) },
    })
  end
  max_length = chunk_length(max_length, name_chunk)
  table.insert(chunks, name_chunk)

  -- status
  if user.status ~= vim.NIL then
    local status_chunk = { { " " } }
    if user.status.emoji ~= vim.NIL then
      table.insert(status_chunk, { user.status.emoji })
      table.insert(status_chunk, { " " })
    end
    if user.status.message ~= vim.NIL then
      table.insert(status_chunk, { user.status.message })
    end
    if #status_chunk > 0 then
      max_length = chunk_length(max_length, status_chunk)
      table.insert(chunks, status_chunk)
    end
  end

  -- bio
  if user.bio ~= vim.NIL then
    for _, line in ipairs(utils.text_wrap(user.bio, max_width - 4)) do
      local bio_line_chunk = { { " " }, { line } }
      max_length = chunk_length(max_length, bio_line_chunk)
      table.insert(chunks, bio_line_chunk)
    end
  end

  -- followers/following
  local follow_chunk = {
    { " " },
    { "Followers: ", "OctoDetailsValue" },
    { tostring(user.followers.totalCount) },
    { " Following: ", "OctoDetailsValue" },
    { tostring(user.following.totalCount) },
  }
  max_length = chunk_length(max_length, follow_chunk)
  table.insert(chunks, follow_chunk)

  -- location
  if user.location ~= vim.NIL then
    local location_chunk = {
      { " " },
      { "🏠 " .. user.location },
    }
    max_length = chunk_length(max_length, location_chunk)
    table.insert(chunks, location_chunk)
  end

  -- company
  if user.company ~= vim.NIL then
    local company_chunk = {
      { " " },
      { "🏢 " .. user.company },
    }
    max_length = chunk_length(max_length, company_chunk)
    table.insert(chunks, company_chunk)
  end

  -- hovercards
  if #user.hovercard.contexts > 0 then
    for _, context in ipairs(user.hovercard.contexts) do
      local hovercard_chunk = {
        { " " },
        { context.message },
      }
      max_length = chunk_length(max_length, hovercard_chunk)
      table.insert(chunks, hovercard_chunk)
    end
  end

  -- twitter
  if user.twitterUsername ~= vim.NIL then
    local twitter_chunk = {
      { " " },
      { "🐦 " .. user.twitterUsername },
    }
    max_length = chunk_length(max_length, twitter_chunk)
    table.insert(chunks, twitter_chunk)
  end

  -- website
  if user.websiteUrl ~= vim.NIL then
    local website_chunk = {
      { " " },
      { "🔗 " .. user.websiteUrl },
    }
    max_length = chunk_length(max_length, website_chunk)
    table.insert(chunks, website_chunk)
  end

  -- badges
  local badges_chunk = {}
  if user.hasSponsorsListing then
    local sponsor_bubble = bubbles.make_bubble("SPONSOR", "OctoBubbleBlue", { margin_width = 1 })
    vim.list_extend(badges_chunk, sponsor_bubble)
  end
  if user.isEmployee then
    local staff_bubble = bubbles.make_bubble("STAFF", "OctoBubblePurple", { margin_width = 1 })
    vim.list_extend(badges_chunk, staff_bubble)
  end
  if #badges_chunk > 0 then
    max_length = chunk_length(max_length, badges_chunk)
    table.insert(chunks, badges_chunk)
  end

  for i = 1, #chunks do
    M.write_block(bufnr, { "" }, i)
  end
  for i = 1, #chunks do
    M.write_virtual_text(bufnr, constants.OCTO_PROFILE_VT_NS, i - 1, chunks[i])
  end
  return #chunks, max_length
end

function M.write_issue_summary(bufnr, issue, opts)
  opts = opts or {}
  local conf = config.values
  local max_length = opts.max_length or 80
  local chunks = {}

  -- repo and date line
  table.insert(chunks, {
    { " " },
    { issue.repository.nameWithOwner, "OctoDetailsValue" },
    { " " .. utils.format_date(issue.createdAt), "OctoDetailsValue" },
  })

  -- issue body
  local state = utils.get_displayed_state(issue.__typename == "Issue", issue.state, issue.stateReason)
  table.insert(chunks, {
    { " " },
    { "[" .. state:gsub("_", " ") .. "] ", utils.state_hl_map[state] },
    { issue.title .. " ", "OctoDetailsLabel" },
    { "#" .. issue.number .. " ", "OctoDetailsValue" },
  })
  table.insert(chunks, { { "" } })

  -- issue body
  local body = vim.split(issue.body, "\n")
  body = table.concat(body, " ")
  body = body:gsub("[%c]", " ")
  body = body:sub(1, max_length - 4 - 2) .. "…"
  table.insert(chunks, {
    { " " },
    { body },
  })
  table.insert(chunks, { { "" } })

  -- labels
  if #issue.labels.nodes > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels.nodes) do
      local label_bubble = bubbles.make_label_bubble(label.name, label.color, { right_margin_width = 1 })
      vim.list_extend(labels, label_bubble)
    end
    table.insert(chunks, labels)
    table.insert(chunks, { { "" } })
  end

  -- PR branches
  if issue.__typename == "PullRequest" then
    table.insert(chunks, {
      { " " },
      { "[", "OctoDetailsValue" },
      { issue.baseRefName, "OctoDetailsLabel" },
      { "] ⟵ [", "OctoDetailsValue" },
      { issue.headRefName, "OctoDetailsLabel" },
      { "]", "OctoDetailsValue" },
    })
    table.insert(chunks, { { "" } })
  end

  -- author line
  if utils.is_blank(issue.author) then
    table.insert(chunks, {
      { " " },
      { conf.ghost_icon or "󰊠 " },
      { "ghost" },
    })
  else
    table.insert(chunks, {
      { " " },
      { conf.user_icon or " " },
      { issue.author.login },
    })
  end

  for i = 1, #chunks do
    M.write_block(bufnr, { "" }, i)
  end
  for i = 1, #chunks do
    M.write_virtual_text(bufnr, constants.OCTO_SUMMARY_VT_NS, i - 1, chunks[i])
  end
  return #chunks
end

local function write_event(bufnr, vt)
  local line = vim.api.nvim_buf_line_count(bufnr) - 1
  M.write_block(bufnr, { "" }, line + 2)
  M.write_virtual_text(bufnr, constants.OCTO_EVENT_VT_NS, line + 1, vt)
end

function M.write_assigned_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  if item.actor.login == item.assignee.login then
    table.insert(vt, { " self-assigned this", "OctoTimelineItemHeading" })
  else
    table.insert(vt, { " assigned this to ", "OctoTimelineItemHeading" })
    table.insert(vt, { item.assignee.login or item.assignee.name, "OctoDetailsLabel" })
  end
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

local get_status_check = function(statusCheckRollup)
  if utils.is_blank(statusCheckRollup) then
    return { "  " }
  end

  local state = statusCheckRollup.state
  local state_info = utils.state_map[state]

  return { state_info.symbol, state_info.hl }
end

function M.write_commit_event(bufnr, item)
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  if item.commit.committer.user ~= vim.NIL then
    -- local commiter_bubble = bubbles.make_user_bubble(
    --   item.commit.committer.user.login,
    --   item.commit.committer.user.login == vim.g.octo_viewer
    -- )
    -- vim.list_extend(vt, commiter_bubble)
    table.insert(vt, {
      item.commit.committer.user.login,
      item.commit.committer.user.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
    })
  elseif item.commit.author ~= vim.NIL and item.commit.author.user ~= vim.NIL then
    table.insert(vt, {
      item.commit.author.user.login,
      item.commit.author.user.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
    })
  end

  table.insert(vt, { " added ", "OctoTimelineItemHeading" })
  table.insert(vt, get_status_check(item.commit.statusCheckRollup))
  table.insert(vt, { item.commit.abbreviatedOid, "OctoDetailsLabel" })
  table.insert(vt, { " ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.commit.messageHeadline, "OctoDetailsLabel" })
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

local function write_issue_or_pr(bufnr, item)
  local vt = {}
  local state = utils.get_displayed_state(item.__typename == "Issue", item.state, item.stateReason, item.isDraft)
  local entry = {
    kind = item.__typename == "Issue" and "issue" or "pull_request",
    obj = item,
  }
  local icon = utils.get_icon(entry)
  table.insert(vt, { "          ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.title, "OctoDetailsLabel" })
  table.insert(vt, { " #" .. tostring(item.number) .. " ", "OctoDetailsValue" })
  table.insert(vt, icon)
  table.insert(vt, { state, utils.state_hl_map[state] })

  write_event(bufnr, vt)
end

local write_reference_commit = function(bufnr, commit)
  local vt = {}
  table.insert(vt, { "          ", "OctoTimelineItemHeading" })
  table.insert(vt, { commit.message, "OctoTimelineItemHeading" })
  table.insert(vt, { " ", "OctoTimelineItemHeading" })
  table.insert(vt, { commit.abbreviatedOid, "OctoTimelineItemHeading" })
  write_event(bufnr, vt)
end

function M.write_referenced_event(bufnr, item)
  if utils.is_blank(item.actor) then
    return
  end

  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  table.insert(vt, {
    item.actor.login,
    item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
  })
  table.insert(vt, { " added a commit to ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.commit.repository.nameWithOwner, "OctoDetailsLabel" })
  table.insert(vt, { " that referenced this issue ", "OctoTimelineItemHeading" })
  table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
  write_reference_commit(bufnr, item.commit)
end

function M.write_cross_referenced_event(bufnr, item)
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  table.insert(vt, {
    item.actor.login,
    item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
  })

  local target = item.target
  local will_close_target = item.willCloseTarget

  if target.__typename == "PullRequest" and not will_close_target then
    table.insert(vt, { " mentioned this pull request ", "OctoTimelineItemHeading" })
    table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
  elseif target.__typename == "PullRequest" then
    table.insert(vt, { " linked a pull request ", "OctoTimelineItemHeading" })
    table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
    table.insert(vt, { " that will close this issue ", "OctoTimelineItemHeading" })
  elseif not will_close_target then
    table.insert(vt, { " mentioned this issue ", "OctoTimelineItemHeading" })
    table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
  else
    table.insert(vt, { " linked an issue ", "OctoTimelineItemHeading" })
    table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
    table.insert(vt, { " that may be closed by this pull request ", "OctoTimelineItemHeading" })
  end

  write_event(bufnr, vt)
  write_issue_or_pr(bufnr, item.source)
end

local write_milestone_event = function(bufnr, item, add)
  local verb, preposition
  if add then
    verb = "added"
    preposition = "to"
  else
    verb = "removed"
    preposition = "from"
  end

  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  table.insert(vt, {
    item.actor.login,
    item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
  })
  table.insert(vt, { " " .. verb .. " this " .. preposition .. " the ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.milestoneTitle, "OctoDetailsLabel" })
  table.insert(vt, { " milestone ", "OctoTimelineItemHeading" })
  table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_milestoned_event(bufnr, item)
  write_milestone_event(bufnr, item, true)
end

function M.write_demilestoned_event(bufnr, item)
  write_milestone_event(bufnr, item, false)
end

function M.write_connected_event(bufnr, item)
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  table.insert(vt, {
    item.actor.login,
    item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
  })

  local subject = item.subject

  if subject.__typename == "PullRequest" then
    table.insert(vt, { " linked a pull request ", "OctoTimelineItemHeading" })
    table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
    table.insert(vt, { " that will close this issue ", "OctoTimelineItemHeading" })
  else
    table.insert(vt, { " linked an issue ", "OctoTimelineItemHeading" })
    table.insert(vt, { utils.format_date(item.createdAt), "OctoDate" })
    table.insert(vt, { " that may be closed by this pull request ", "OctoTimelineItemHeading" })
  end

  write_event(bufnr, vt)
  write_issue_or_pr(bufnr, item.subject)
end

function M.write_renamed_title_event(bufnr, item)
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  if utils.is_blank(item.actor) then
    table.insert(vt, { "Title renamed", "OctoTimelineItemHeading" })
    write_event(bufnr, vt)
    return
  end

  table.insert(vt, {
    item.actor.login,
    item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser",
  })
  table.insert(vt, { " changed the title ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.previousTitle, "OctoStrikethrough" })
  table.insert(vt, { " ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.currentTitle, "OctoDetailsLabel" })
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_merged_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  table.insert(vt, { " merged commit ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.commit.abbreviatedOid, "OctoDetailsLabel" })
  table.insert(vt, { " into ", "OctoTimelineItemHeading" })
  table.insert(vt, { item.mergeRefName, "OctoTimelineItemHeading" })
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_closed_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  table.insert(vt, { " closed this ", "OctoTimelineItemHeading" })
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_labeled_events(bufnr, items, action)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local labels_by_actor = {}
  for _, item in ipairs(items) do
    local key = item.actor ~= vim.NIL and item.actor.login or vim.NIL
    local labels = labels_by_actor[key] or {}
    table.insert(labels, item.label)
    labels_by_actor[key] = labels
  end

  for _, actor in ipairs(vim.tbl_keys(labels_by_actor)) do
    local vt = {}
    local conf = config.values
    table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
    table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
    --vim.list_extend(vt, actor_bubble)
    if actor ~= vim.NIL then
      table.insert(vt, { actor, actor == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
      table.insert(vt, { " " .. action .. " ", "OctoTimelineItemHeading" })
    else
      table.insert(vt, { action .. " ", "OctoTimelineItemHeading" })
    end
    local labels = labels_by_actor[actor]
    for _, label in ipairs(labels) do
      local label_bubble = bubbles.make_label_bubble(label.name, label.color, { right_margin_width = 1 })
      vim.list_extend(vt, label_bubble)
    end
    table.insert(vt, { #labels > 1 and "labels" or "label", "OctoTimelineItemHeading" })
    write_event(bufnr, vt)
  end
end

function M.write_reopened_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  table.insert(vt, { " reopened this ", "OctoTimelineItemHeading" })
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_review_requested_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )

  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  if item.requestedReviewer == vim.NIL then
    table.insert(vt, { " requested a review", "OctoTimelineItemHeading" })
  else
    table.insert(vt, { " requested a review from ", "OctoTimelineItemHeading" })
    table.insert(vt, { item.requestedReviewer.login or item.requestedReviewer.name, "OctoUser" })
  end
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_review_request_removed_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  if item.requestedReviewer == vim.NIL then
    table.insert(vt, { " removed a review request", "OctoTimelineItemHeading" })
  else
    table.insert(vt, { " removed a review request for ", "OctoTimelineItemHeading" })
    table.insert(vt, { item.requestedReviewer.login or item.requestedReviewer.name, "OctoUser" })
  end
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_review_dismissed_event(bufnr, item)
  -- local actor_bubble = bubbles.make_user_bubble(
  --   item.actor.login,
  --   item.actor.login == vim.g.octo_viewer
  -- )
  local vt = {}
  local conf = config.values
  table.insert(vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(vt, { "EVENT: ", "OctoTimelineItemHeading" })
  --vim.list_extend(vt, actor_bubble)
  table.insert(vt, { item.actor.login, item.actor.login == vim.g.octo_viewer and "OctoUserViewer" or "OctoUser" })
  table.insert(vt, { " dismissed a review", "OctoTimelineItemHeading" })
  if item.dismissalMessage ~= vim.NIL then
    table.insert(vt, { " [", "OctoTimelineItemHeading" })
    table.insert(vt, { item.dismissalMessage, "OctoUser" })
    table.insert(vt, { "]", "OctoTimelineItemHeading" })
  end
  table.insert(vt, { " " .. utils.format_date(item.createdAt), "OctoDate" })
  write_event(bufnr, vt)
end

function M.write_threads(bufnr, threads)
  local comment_start, comment_end

  -- print each of the threads
  for _, thread in ipairs(threads) do
    local thread_start, thread_end
    for _, comment in ipairs(thread.comments.nodes) do
      -- augment comment details
      comment.path = thread.path
      comment.diffSide = thread.diffSide

      -- review thread header
      if utils.is_blank(comment.replyTo) then
        local start_line = not utils.is_blank(thread.originalStartLine) and thread.originalStartLine
          or thread.originalLine
        local end_line = thread.originalLine
        comment.start_line = start_line
        comment.end_line = end_line

        -- write thread header
        M.write_review_thread_header(bufnr, {
          path = thread.path,
          start_line = start_line,
          end_line = end_line,
          isOutdated = thread.isOutdated,
          isResolved = thread.isResolved,
          resolvedBy = thread.resolvedBy,
          commit = comment.originalCommit.abbreviatedOid,
        })

        -- write empty line
        M.write_block(bufnr, { "" })

        -- write snippet
        thread_start, thread_end =
          M.write_thread_snippet(bufnr, comment.diffHunk, nil, start_line, end_line, thread.diffSide)
      end

      comment_start, comment_end = M.write_comment(bufnr, comment, "PullRequestReviewComment")
      folds.create(bufnr, comment_start + 1, comment_end, true)
      thread_end = comment_end
    end
    folds.create(bufnr, thread_start - 1, thread_end - 1, not thread.isCollapsed)

    -- mark the thread region
    local thread_mark_id = vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_THREAD_NS, thread_start - 1, 0, {
      end_line = thread_end,
      end_col = 0,
    })
    local buffer = octo_buffers[bufnr]
    -- store thread info in the octo buffer for later reference
    buffer.threadsMetadata[tostring(thread_mark_id)] = ThreadMetadata:new {
      threadId = thread.id,
      replyTo = thread.comments.nodes[1].id,
      replyToRest = utils.extract_rest_id(thread.comments.nodes[1].url),
      reviewId = thread.comments.nodes[1].pullRequestReview.id,
      path = thread.path,
      line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine,
    }
  end

  return comment_end
end

function M.write_virtual_text(bufnr, ns, line, chunks, mode)
  mode = mode or "extmark"
  if mode == "extmark" then
    pcall(
      vim.api.nvim_buf_set_extmark,
      bufnr,
      ns,
      line,
      0,
      { virt_text = chunks, virt_text_pos = "overlay", hl_mode = "combine" }
    )
  elseif mode == "vt" then
    pcall(vim.api.nvim_buf_set_virtual_text, bufnr, ns, line, chunks, {})
  end
end

return M
