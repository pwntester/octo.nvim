local CommentMetadata = require("octo.model.comment-metadata").CommentMetadata
local ThreadMetadata = require("octo.model.thread-metadata").ThreadMetadata
local BodyMetadata = require("octo.model.body-metadata").BodyMetadata
local TitleMetadata = require("octo.model.title-metadata").TitleMetadata
local constants = require "octo.constants"
local config = require "octo.config"
local utils = require "octo.utils"
local logins = require "octo.logins"
local folds = require "octo.folds"
local bubbles = require "octo.ui.bubbles"
local notify = require "octo.notify"
local TextChunkBuilder = require "octo.ui.text-chunk-builder"
local vim = vim

local M = {}

-- Track if we've already warned about ProjectV2 config
local projects_v2_config_warned = false

--- Show a one-time warning about enabling ProjectsV2 config
local function warn_projects_v2_config()
  if not projects_v2_config_warned and not config.values.default_to_projects_v2 then
    projects_v2_config_warned = true
    notify.info "ProjectsV2 timeline events are disabled. Enable them by setting 'default_to_projects_v2 = true' in your Octo config."
  end
end

--- Write text in a buffer, append to end unless specified, and optionally set
--- an extmark for the block.
---@param bufnr integer? buffer number, defaults to current buffer
---@param lines string[] | string lines to write
---@param line? integer starting line number
---@param mark? boolean whether to set extmark for the block
---@return integer? extmark_id
function M.write_block(bufnr, lines, line, mark)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_buf_line_count(bufnr) + 1
  mark = mark or false

  if type(lines) == "string" then
    lines = vim.split(lines, "\n", { plain = true })
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
    -- (except for title where we can't place initial mark on line -1)

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

--- Add a line to details table if value is not nil
--- Examples of usage:
--- add_details_line(details, "Label", "value")
--- add_details_line(details, "Label", function() return "value" end)
---@type (fun(
--- details: [string, string][][], label: string, value: nil|string|integer|(fun(): nil|string|integer),
---): nil)|(fun(
--- details: [string, string][][], label: string, value: boolean|(fun(): boolean), kind: "boolean",
--- ): nil)|(fun(
---): nil)|(fun(
--- details: [string, string][][], label: string, value: string|(fun(): string), kind: "date",
--- ): nil)|(fun(
--- details: [string, string][][], label: string, value: {name: string, color: string}|(fun(): {name: string, color: string}), kind: "label",
--- ): nil)|(fun(
--- details: [string, string][][], label: string, value: {name: string, color: string}[]|(fun(): {name: string, color: string}[]), kind: "labels",
--- ): nil)
local function add_details_line(details, label, value, kind)
  if type(value) == "function" then
    ---@diagnostic disable-next-line: no-unknown
    value = value()
  end
  if value ~= vim.NIL and value ~= nil then
    if kind == "date" then
      value = value --[[@as string]]
      value = utils.format_date(value)
    end
    local vt = { { label .. ": ", "OctoDetailsLabel" } }
    if kind == "label" then
      vim.list_extend(vt, bubbles.make_label_bubble(value.name, value.color, { right_margin_width = 1 }))
    elseif kind == "labels" then
      value = value --[[@as {name: string, color: string}[] ]]
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

---@param bufnr integer
---@param release octo.Release
local function write_release_details(bufnr, release)
  local details = {}
  -- clear namespace and set vt
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, 0, -1)

  table.insert(details, {
    { "Repo: ", "OctoDetailsLabel" },
    { " " .. (select(2, utils.parse_url(release.url)) or ""), "OctoDetailsValue" },
  })
  local author_vt = { { "Publisher", "OctoDetailsLabel" } }
  local author_bubble = bubbles.make_user_bubble(release.author.login)
  vim.list_extend(author_vt, author_bubble)
  table.insert(details, author_vt)
  add_details_line(details, "Published", release.publishedAt, "date")
  add_details_line(details, "Tag", release.tagName)
  add_details_line(details, "Commit", release.tagCommit.abbreviatedOid)

  M.write_detail_table { bufnr = bufnr, details = details, offset = 3 }
end

---@param bufnr integer
---@param release octo.Release
function M.write_release(bufnr, release)
  M.write_title(bufnr, release.name, 1)
  if release.isPrerelease then
    vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_TITLE_VT_NS, 0, 0, {
      virt_text = { { "[Pre-release]", "OctoStatePending" } },
    })
  end
  if release.isLatest then
    vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_TITLE_VT_NS, 0, 0, {
      virt_text = { { "[Latest]", "OctoStateOpen" } },
    })
  end
  write_release_details(bufnr, release)
  M.write_body_agnostic(bufnr, release.description)
  table.sort(release.releaseAssets.nodes, function(a, b)
    return vim.stricmp(a.name, b.name) < 0
  end)
  for _, asset in ipairs(release.releaseAssets.nodes) do
    M.write_block(bufnr, {
      "[" .. asset.name .. "]" .. "(" .. asset.downloadUrl .. ")",
    })
    local parts = {
      utils.format_large_int(asset.downloadCount, false) .. " ",
      utils.format_large_int(asset.size, true) .. "B",
      utils.format_date(asset.updatedAt),
    }
    local line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, 0, {
      virt_text = { { table.concat(parts, " | ") } },
      virt_text_pos = "eol_right_align",
    })
  end
  M.write_block(bufnr, { "" })
  M.write_block(bufnr, { "" })
  local line = vim.api.nvim_buf_line_count(bufnr)
  M.write_reactions(bufnr, release.reactionGroups, line)
end

---@param bufnr integer
---@param discussion octo.Discussion
function M.write_discussion_details(bufnr, discussion)
  local details = {}

  -- clear namespace and set vt
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, 0, -1)

  table.insert(details, {
    { "Repo: ", "OctoDetailsLabel" },
    { " " .. (select(2, utils.parse_url(discussion.url)) or ""), "OctoDetailsValue" },
  })

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
  add_details_line(details, "Replies", utils.count_discussion_replies(discussion))

  M.write_detail_table { bufnr = bufnr, details = details, offset = 3 }
end

---@param opts {
---  bufnr: integer,
---  details: [string, string][][],
---  offset: integer,
---}
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

--- Write virtual text at given line in buffer
---@param bufnr integer
---@param obj octo.fragments.DiscussionDetails
---@param line integer
function M.write_upvotes(bufnr, obj, line)
  -- clear namespace and set vt
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)

  local upvote_symbol = " "

  local upvotes = obj.upvoteCount
  -- local viewer_did_upvote = obj.viewerHasUpvoted

  local upvotes_vt = {
    { upvote_symbol, "OctoDetailsLabel" },
    { " " .. upvotes, "OctoDetailsValue" },
  }
  M.write_block(bufnr, { "" }, line)
  M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line, upvotes_vt)
end

---@param bufnr integer
---@param obj octo.Discussion
---@param line integer
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

---@param bufnr integer
---@param repo octo.Repository
function M.write_repo(bufnr, repo)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  ---@type [string, string][][]
  local details = {}

  -- clear virtual texts
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REPO_VT_NS, 0, -1)

  add_details_line(details, "Name", repo.nameWithOwner)
  add_details_line(details, "Description", repo.description)
  local defaultBranchRefName ---@type string?
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
        vim.bo[bufnr].modified = false
      end
    end)
  end
end

--- Write virtual text title at given line in buffer
---@param bufnr integer
---@param title string
---@param line integer
function M.write_title(bufnr, title, line)
  local title_mark = M.write_block(bufnr, { title, "" }, line, true)
  vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_TITLE_NS, 0, 0, {
    end_line = 1,
    hl_group = "OctoIssueTitle",
  })
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

---@param state string
---@param state_reason? string
---@param is_issue? boolean
---@param is_discussion? boolean
---@return table|nil
local function get_state_icon(state, state_reason, is_issue, is_discussion)
  if is_discussion then
    if state == "OPEN" then
      return nil
    elseif state == "ANSWERED" then
      return utils.icons.discussion.answered
    elseif state == "RESOLVED" then
      return utils.icons.discussion.resolved
    elseif state == "OUTDATED" then
      return utils.icons.discussion.outdated
    elseif state == "DUPLICATE" then
      return utils.icons.discussion.duplicate
    end
  elseif is_issue then
    if state == "OPEN" then
      return utils.icons.issue.open
    elseif state == "CLOSED" or state == "NOT_PLANNED" or state == "COMPLETED" then
      return (state_reason == "NOT_PLANNED" or state == "NOT_PLANNED") and utils.icons.issue.not_planned
        or utils.icons.issue.closed
    end
  else
    if state == "OPEN" then
      return utils.icons.pull_request.open
    elseif state == "MERGED" then
      return utils.icons.pull_request.merged
    elseif state == "CLOSED" then
      return utils.icons.pull_request.closed
    elseif state == "DRAFT" then
      return utils.icons.pull_request.draft
    end
  end
end

--- Write virtual text state at given line in buffer
---@param bufnr? integer
---@param state? string
---@param number? integer
function M.write_state(bufnr, state, number)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]

  if not buffer then
    return
  end

  ---@type octo.Issue|octo.PullRequest|octo.Discussion
  local obj
  if buffer:isIssue() then
    obj = buffer:issue()
  elseif buffer:isPullRequest() then
    obj = buffer:pullRequest()
  elseif buffer:isDiscussion() then
    obj = buffer:discussion()
  else
    return
  end

  state = state or obj.state
  number = number or buffer.number

  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_TITLE_VT_NS, 0, -1)

  local title_vt = {
    { tostring(number), "OctoIssueId" },
    { " " },
  }

  local is_issue = buffer:isIssue()
  ---@type string
  local display_state

  if buffer:isDiscussion() then
    display_state = state
  else
    display_state = utils.get_displayed_state(is_issue, obj.state, obj.stateReason, obj.isDraft)
  end

  local is_discussion = buffer:isDiscussion()

  -- Skip showing state for open discussions
  if not (is_discussion and display_state == "OPEN") then
    local builder = TextChunkBuilder:new()
    builder:state_with_icon(display_state, obj.stateReason, obj.isDraft, function(state, state_reason)
      return get_state_icon(state, state_reason, is_issue, is_discussion)
    end)
    vim.list_extend(title_vt, builder:build())
  end

  vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_TITLE_VT_NS, 0, 0, {
    virt_text = title_vt,
  })
end

---@param bufnr integer
---@param body string
---@param line? integer
---@param viewer_can_update? boolean
function M.write_body_agnostic(bufnr, body, line, viewer_can_update)
  body = utils.trim(body)
  if vim.startswith(body, constants.NO_BODY_MSG) or utils.is_blank(body) then
    body = " "
  end
  local description = body:gsub("\r\n", "\n")
  local lines = vim.split(description, "\n", { plain = true })
  vim.list_extend(lines, { "" })
  local desc_mark = M.write_block(bufnr, lines, line, true)
  local buffer = octo_buffers[bufnr]
  if buffer then
    buffer.bodyMetadata = BodyMetadata:new {
      savedBody = description,
      body = description,
      dirty = false,
      extmark = desc_mark,
      viewerCanUpdate = viewer_can_update,
    }
  end
end

---@param bufnr integer
---@param issue octo.Issue|octo.PullRequest|octo.Discussion
---@param line? integer
function M.write_body(bufnr, issue, line)
  M.write_body_agnostic(bufnr, issue.body, line, issue.viewerCanUpdate)
end

---@param bufnr integer
---@param reaction_groups table[]
---@param line integer
---@return integer?
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
      ---@type string
      local icon = utils.reaction_map[group.content]
      local bubble = bubbles.make_reaction_bubble(icon, group.viewerHasReacted)
      vim.list_extend(reactions_vt, bubble)
      table.insert(reactions_vt, { " " .. group.users.totalCount .. " ", "NormalFloat" })
    end
  end
  M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, reactions_vt)
  return line
end

---@param association octo.CommentAuthorAssociation
local function format_author_association(association)
  if association == "FIRST_TIME_CONTRIBUTOR" then
    return "First-time contributor"
  else
    return utils.title_case(utils.remove_underscore(association))
  end
end

local function detect_issue_from_url(url)
  local keyword = "issues"
  return url:find(keyword, 1, true) ~= nil
end

---@param details [string, string][][]
---@param subscription_state octo.SubscriptionState
local function add_subscription_detail(details, subscription_state)
  local subscribed_label ---@type string
  if subscription_state == "IGNORED" then
    subscribed_label = "Never"
  elseif subscription_state == "SUBSCRIBED" then
    subscribed_label = "All activity"
  elseif subscription_state == "UNSUBSCRIBED" then
    subscribed_label = "Only participating and @mentioned"
  end
  add_details_line(details, "Subscribed", subscribed_label)
end

---@param details [string, string][][]
---@param is_issue boolean
---@param state string
---@param state_reason? string
---@param is_draft? boolean
local function add_status_detail(details, is_issue, state, state_reason, is_draft)
  local display_state = utils.get_displayed_state(is_issue, state, state_reason, is_draft)

  TextChunkBuilder:new()
    :detail_label("Status")
    :state_with_icon(display_state, state_reason, is_draft, function(s, sr)
      return get_state_icon(s, sr, is_issue, false)
    end)
    :write_detail_line(details)
end

--- Write issue or PR details virtual text in buffer
---@param bufnr integer
---@param issue octo.PullRequest|octo.Issue
---@param update? true
---@param include_status? boolean
function M.write_details(bufnr, issue, update, include_status)
  vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DETAILS_VT_NS, 0, -1)

  local is_issue = detect_issue_from_url(issue.url)
  local details = {} ---@type [string, string][][]

  if include_status then
    add_status_detail(details, is_issue, issue.state, issue.stateReason, issue.isDraft)
  end

  table.insert(details, {
    { "Repo: ", "OctoDetailsLabel" },
    { " " .. (select(2, utils.parse_url(issue.url)) or ""), "OctoDetailsValue" },
  })

  -- author
  local author_vt = { { "Created by: ", "OctoDetailsLabel" } }
  local opts = {}

  issue.author = logins.format_author(issue.author)
  if issue.author.login == "ghost" then
    opts = { ghost = true }
  end

  local author_bubble = bubbles.make_user_bubble(issue.author.login, issue.viewerDidAuthor, opts)

  vim.list_extend(author_vt, author_bubble)
  if not utils.is_blank(issue.authorAssociation) and issue.authorAssociation ~= "NONE" then
    table.insert(author_vt, { " (" .. format_author_association(issue.authorAssociation) .. ")", "OctoDetailsLabel" })
  end
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

  -- projects v2
  if issue.projectItems and #issue.projectItems.nodes > 0 then
    local projects_vt = {
      { "Projects (v2): ", "OctoDetailsLabel" },
    }
    --local project_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("NormalFloat")), "bg#"):sub(2)
    --local column_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("Comment")), "fg#"):sub(2)
    for idx, item in ipairs(issue.projectItems.nodes) do
      if item.project ~= vim.NIL and item.project then
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

  --- Parent
  if is_issue then
    local parent = issue.parent
    local builder = TextChunkBuilder:new():detail_label "Parent"

    if not utils.is_blank(parent) then
      local obj = parent --[[@as EntryObject]]
      local icon = utils.get_icon { kind = "issue", obj = obj }
      builder:text(icon[1], icon[2]):detail_value("#" .. tostring(parent.number) .. " " .. parent.title .. " ")
    else
      builder:detail_missing "None yet"
    end

    builder:write_detail_line(details)
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

  -- issue type
  local issue_type_vt = {
    { "Type: ", "OctoDetailsLabel" },
  }

  if not utils.is_blank(issue.issueType) then
    local issue_type = issue.issueType
    ---@diagnostic disable-next-line
    local issue_type_bubble = bubbles.make_label_bubble(issue_type.name, issue_type.color)
    vim.list_extend(issue_type_vt, issue_type_bubble)
  else
    table.insert(issue_type_vt, { "No type", "OctoMissingDetails" })
  end
  if is_issue then
    table.insert(details, issue_type_vt)
  end

  -- additional details for pull requests
  if issue.commits then
    -- reviewers
    local reviewers = {} ---@type table<string, string[]>
    ---@param name string
    ---@param state string
    local function collect_reviewer(name, state)
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
    ---@type (octo.PullRequestTimelineItem|octo.IssueTimelineItem)[]
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
      ---@type string[]
      local reviewer_names = vim.tbl_keys(reviewers)
      for _, name in ipairs(reviewer_names) do
        local strongest_review = utils.calculate_strongest_review_state(reviewers[name])
        name = logins.format_author({ login = name }).login
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

    ---Development
    local development_vt = {
      { "Development: ", "OctoDetailsLabel" },
    }
    if issue.closingIssuesReferences and issue.closingIssuesReferences.totalCount > 0 then
      for _, closing_issue in ipairs(issue.closingIssuesReferences.nodes) do
        local obj = closing_issue --[[@as EntryObject]]
        local icon = utils.get_icon { kind = "issue", obj = obj }
        table.insert(development_vt, icon)
        table.insert(
          development_vt,
          { " #" .. tostring(closing_issue.number) .. " " .. closing_issue.title .. " ", "OctoDetailsValue" }
        )
      end
    else
      table.insert(development_vt, { "None yet", "OctoMissingDetails" })
    end
    table.insert(details, development_vt)

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
      ---@type string
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

  add_subscription_detail(details, issue.viewerSubscription)

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

---@param bufnr integer
---@param comment octo.ReviewThreadCommentFragment|octo.fragments.DiscussionComment|octo.fragments.PullRequestReview|octo.fragments.IssueComment|{
---  replyToRest: string,
---  start_line: integer,
---  end_line: integer,
---  diffSide: string,
---}
---@param kind string
---@param line? integer
function M.write_comment(bufnr, comment, kind, line)
  -- possible kinds:
  ---- IssueComment
  ---- PullRequestReview
  ---- PullRequestReviewComment
  ---- PullRequestComment (regular comment (not associated to any review) to a PR review comment)
  ---- DiscussionComment

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
    comment.author = logins.format_author(comment.author)
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
    comment.author = logins.format_author(comment.author)
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
    comment.author = logins.format_author(comment.author)
    table.insert(header_vt, { "COMMENT: ", "OctoTimelineItemHeading" })
    table.insert(header_vt, { comment.author.login, comment.viewerDidAuthor and "OctoUserViewer" or "OctoUser" })
    table.insert(header_vt, { " " .. utils.format_date(comment.createdAt), "OctoDate" })
    if not comment.viewerCanUpdate then
      table.insert(header_vt, { " ", "OctoRed" })
    end
  elseif kind == "IssueComment" or kind == "DiscussionComment" then
    -- Issue comments
    table.insert(header_vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
    if utils.is_blank(comment.replyTo) then
      table.insert(header_vt, { "COMMENT: ", "OctoTimelineItemHeading" })
    else
      table.insert(header_vt, { "REPLY: ", "OctoTimelineItemHeading" })
    end
    --vim.list_extend(header_vt, author_bubble)
    comment.author = logins.format_author(comment.author)
    table.insert(header_vt, { comment.author.login, comment.viewerDidAuthor and "OctoUserViewer" or "OctoUser" })
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
  local content = vim.split(comment_body, "\n", { plain = true })
  vim.list_extend(content, { "" })
  local comment_mark = M.write_block(bufnr, content, line, true)

  line = line + #content

  -- reactions
  local reaction_line ---@type integer?
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
      author = "",
      id = comment.id,
      databaseId = comment.databaseId,
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

---@param bufnr integer
---@param review octo.fragments.PullRequestReview
function M.write_review_decision(bufnr, review)
  local line = vim.api.nvim_buf_line_count(bufnr) + 1
  local conf = config.values
  M.write_block(bufnr, { "", "" }, line)
  local header_vt = {}
  local state_bubble =
    bubbles.make_bubble(utils.state_msg_map[review.state], utils.state_hl_map[review.state] .. "Bubble")
  table.insert(header_vt, { conf.timeline_marker .. " ", "OctoTimelineMarker" })
  table.insert(header_vt, { "REVIEW: ", "OctoTimelineItemHeading" })
  table.insert(header_vt, {
    review.author.login,
    review.viewerDidAuthor and "OctoUserViewer" or "OctoUser",
  })
  table.insert(header_vt, { " ", "OctoTimelineItemHeading" })
  vim.list_extend(header_vt, state_bubble)
  table.insert(header_vt, { " " .. utils.format_date(review.createdAt), "OctoDate" })

  local comment_vt_ns = vim.api.nvim_create_namespace ""
  M.write_virtual_text(bufnr, comment_vt_ns, line - 1, header_vt)
end

---@param diffhunk_lines string[]
local function find_snippet_range(diffhunk_lines)
  local conf = config.values
  local context_lines = conf.snippet_context_lines or 4
  local snippet_start ---@type integer?
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

---Creates the highlight, content combinations for the given content lines according to the treesitter highlight captures.
---The return value is list for each line, and within that a list of the highlight name + content tuples for that line.
---@param content_lines string[] Content to highlight
---@param lang string? Treesitter language name
---@return [string, string[]][][] highlights
local function highlight_content(content_lines, lang)
  local function get_unhighlighted_ranges()
    local unhighlighted_ranges = {} ---@type [string, string[]][][]
    for i = 1, #content_lines do
      unhighlighted_ranges[#unhighlighted_ranges + 1] = { { content_lines[i], {} } }
    end
    return unhighlighted_ranges
  end
  if not lang then
    return get_unhighlighted_ranges()
  end
  local content = table.concat(content_lines, "\n")
  if not vim.treesitter.language.add(lang) then
    return get_unhighlighted_ranges()
  end
  local parser = vim.treesitter.get_string_parser(content, lang)
  local parsers = parser:parse()
  if not parsers then
    return get_unhighlighted_ranges()
  end
  ---@class HighlightRange
  ---@field start_row integer
  ---@field start_col integer
  ---@field end_row integer
  ---@field end_col integer

  local highlight_ranges = {} ---@type [string, HighlightRange][]
  -- Get the highlight ranges from the treesitter highlights query.
  for _, tree in pairs(parsers) do
    local root = tree:root()

    local query = vim.treesitter.query.get(lang, "highlights")
    if not query then
      goto continue
    end

    for id, node, _ in query:iter_captures(root, content, 0, -1) do
      local capture = query.captures[id]
      if capture then
        local start_row, start_col, end_row, end_col = node:range()
        highlight_ranges[#highlight_ranges + 1] = {
          "@" .. capture .. "." .. query.lang,
          {
            -- HACK: Adding 1 somehow aligns the highlight ranges correctly.
            start_row = start_row + 1,
            start_col = start_col,
            end_row = end_row + 1,
            end_col = end_col,
          },
        }
      end
    end
    ::continue::
  end
  if #highlight_ranges == 0 then
    return get_unhighlighted_ranges()
  end
  -- Create a list of highlight boundaries (when they start and stop) from the ranges above.
  local boundaries = {} ---@type {row: integer, col: integer, is_start: boolean, capture: string, range_idx: integer}[]

  for i, range in ipairs(highlight_ranges) do
    local capture, range_data = range[1], range[2]
    -- Add start boundary
    boundaries[#boundaries + 1] = {
      row = range_data.start_row,
      col = range_data.start_col,
      is_start = true,
      capture = capture,
      range_idx = i,
    }
    -- Add end boundary
    boundaries[#boundaries + 1] = {
      row = range_data.end_row,
      col = range_data.end_col,
      is_start = false,
      capture = capture,
      range_idx = i,
    }
  end

  -- Sort boundaries by position so that we can turn on highlights in the correct order as we iterate.
  table.sort(boundaries, function(a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    if a.col ~= b.col then
      return a.col < b.col
    end
    -- Make sure start comes before end for single column highlights.
    return a.is_start and not b.is_start
  end)

  ---@type {capture: string, range_idx: integer}[]
  local active_ranges = {} -- Tracks which highlight ranges are currently active
  local last_range_start = { row = 1, col = 1 }

  local highlights = {} ---@type [string, string[]][][]
  local content_line_idx = 1
  -- Prefill the highlights to save some empty table checks.
  while content_line_idx <= #content_lines do
    highlights[#highlights + 1] = {}
    content_line_idx = content_line_idx + 1
  end
  for _, boundary in ipairs(boundaries) do
    -- Add the highlights for the content from the last_range_start to the current boundary
    -- according to the active_ranges. The conditional here is to ensure we only add new content.
    if last_range_start.col <= boundary.col and last_range_start.row <= boundary.row then
      -- Collect current highlights.
      local captures = {} ---@type string[]
      -- TODO: The highlighting ordering here matters, but sometimes is incorrect.
      -- For example a function call highlight should override a variable highlight, but sometimes
      -- this ends up being the other way around.
      for _, range in ipairs(active_ranges) do
        table.insert(captures, 1, range.capture)
      end
      -- Collect the content from the previous row and column to the boundary row and column.
      local cur_row, cur_col = last_range_start.row, last_range_start.col
      while cur_row < boundary.row do
        local cur_line = content_lines[cur_row]:sub(cur_col)
        highlights[cur_row][#highlights[cur_row] + 1] = { cur_line, captures }
        cur_col = 1
        cur_row = cur_row + 1
      end
      local cur_line = content_lines[cur_row]:sub(cur_col, boundary.col)
      highlights[cur_row][#highlights[cur_row] + 1] = { cur_line, captures }
      -- Step the last_range_start forward to ensure we only add new content.
      if boundary.col == content_lines[boundary.row]:len() then
        last_range_start = { row = boundary.row + 1, col = 1 }
      else
        last_range_start = { row = boundary.row, col = boundary.col + 1 }
      end
    end

    -- Update active ranges.
    if boundary.is_start then
      -- Add range to active list
      active_ranges[#active_ranges + 1] = {
        capture = boundary.capture,
        range_idx = boundary.range_idx,
      }
    else
      -- Remove range from active list
      for i, active in ipairs(active_ranges) do
        if active.range_idx == boundary.range_idx then
          table.remove(active_ranges, i)
          break
        end
      end
    end
  end
  -- Just in case, we add additional unhighlighted content that was not captured to make sure the highlights array match the content_lines array.
  while last_range_start.row < #content_lines do
    local cur_line = content_lines[last_range_start.row]:sub(last_range_start.col)
    highlights[last_range_start.row][#highlights[last_range_start.row] + 1] = { cur_line, {} }
    last_range_start.col = 1
    last_range_start.row = last_range_start.row + 1
  end
  if last_range_start.row == #content_lines and last_range_start.col <= content_lines[last_range_start.row]:len() then
    local cur_line = content_lines[last_range_start.row]:sub(last_range_start.col)
    highlights[last_range_start.row][#highlights[last_range_start.row] + 1] = { cur_line, {} }
  end

  return highlights
end

---Highlights a git diffhunk with the given treesitter language.
---@param diffhunk_lines string[]
---@param lang string?
local function highlight_diff_lines(diffhunk_lines, lang)
  -- Separate the diffhunk into header, addition, and deletion lines.
  local header_content_lines = {} ---@type string[]
  local header_content_line_map = {} ---@type table<integer, integer>
  local addition_content_lines = {} ---@type string[]
  local addition_content_line_map = {} ---@type table<integer, integer>
  local deletion_content_lines = {} ---@type string[]
  local deletion_content_line_map = {} ---@type table<integer, integer>
  for line_idx, line in ipairs(diffhunk_lines) do
    if vim.startswith(line, "@@") then
      local index = string.find(line, "@[^@]*$")
      local content = string.sub(line, index + 1)
      header_content_lines[#header_content_lines + 1] = content
      header_content_line_map[line_idx] = #header_content_lines
    elseif vim.startswith(line, "+") then
      local content = line:gsub("^.", " ")
      addition_content_lines[#addition_content_lines + 1] = content
      addition_content_line_map[line_idx] = #addition_content_lines
    elseif vim.startswith(line, "-") then
      local content = line:gsub("^.", " ")
      deletion_content_lines[#deletion_content_lines + 1] = content
      deletion_content_line_map[line_idx] = #deletion_content_lines
    else
      addition_content_lines[#addition_content_lines + 1] = line
      addition_content_line_map[line_idx] = #addition_content_lines
      deletion_content_lines[#deletion_content_lines + 1] = line
      deletion_content_line_map[line_idx] = #deletion_content_lines
    end
  end
  -- Highlight the content separately to attempt to make the code being highlighted as correct as possible.
  -- NOTE: This could potentially be non-performant, in which case we may want to disregard separating the highlight calculations.
  local header_highlights = highlight_content(header_content_lines, lang)
  local addition_highlights = highlight_content(addition_content_lines, lang)
  local deletion_highlights = highlight_content(deletion_content_lines, lang)
  local highlights = {} ---@type [string, string[]][][]
  for line_idx = 1, #diffhunk_lines do
    if header_content_line_map[line_idx] ~= nil then
      local header_highlight = header_highlights[header_content_line_map[line_idx]]
      highlights[#highlights + 1] = header_highlight
      -- NOTE: Preferring addition over deletion for the unedited lines. Unsure how to determine which is better.
    elseif addition_content_line_map[line_idx] ~= nil then
      local addition_highlight = addition_highlights[addition_content_line_map[line_idx]]
      highlights[#highlights + 1] = addition_highlight
    elseif deletion_content_line_map[line_idx] ~= nil then
      local deletion_highlight = deletion_highlights[deletion_content_line_map[line_idx]]
      highlights[#highlights + 1] = deletion_highlight
    else
      utils.error "Could not find line in diff"
    end
  end
  return highlights
end

---@param bufnr integer
---@param diffhunk string
---@param diffhunk_lang string?
---@param start_line integer?
---@param comment_start integer
---@param comment_end integer
---@param comment_side "RIGHT" | "LEFT"
---@return integer thread_start_line
---@return integer thread_end_line
function M.write_thread_snippet(bufnr, diffhunk, diffhunk_lang, start_line, comment_start, comment_end, comment_side)
  -- this function will print a diff snippet from the diff hunk.
  -- we need to use the original positions for comment_start and comment_end
  -- since the diff hunk always use the original positions.

  start_line = start_line or vim.api.nvim_buf_line_count(bufnr) + 1
  if not diffhunk or diffhunk == "" then
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
  local side_lines ---@type table<integer, integer>
  if comment_side == "RIGHT" then
    side_lines = map.right_side_lines
  elseif comment_side == "LEFT" then
    side_lines = map.left_side_lines
  end
  ---@type integer, integer
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
    -- could not find comment start line in the diff hunk,
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
  local vt_lines = {} ---@type [string, string[]][]
  table.insert(vt_lines, { { string.format("┌%s┐", string.rep("─", max_length + 2)) } })
  local highlights = highlight_diff_lines(diffhunk_lines, diffhunk_lang)
  ---Get the diff highlights for a particular line with an additional highlight.
  ---NOTE: this could also be hardcoded inside highlight_diff_lines to abstract this away.
  ---@param stacked_highlight string?
  ---@param line_idx integer
  local function get_content_highlight(stacked_highlight, line_idx)
    local highlight_ranges = highlights[line_idx]
    local stacked_highlight_ranges = {} ---@type [string, string[]][]
    for _, range in ipairs(highlight_ranges) do
      local highlight_range = vim.deepcopy(range[2])
      if stacked_highlight then
        highlight_range[#highlight_range + 1] = stacked_highlight
      end
      stacked_highlight_ranges[#stacked_highlight_ranges + 1] = { range[1], highlight_range }
    end
    return stacked_highlight_ranges
  end
  for i = snippet_start, snippet_end do
    local line = diffhunk_lines[i]
    if not line then
      break
    end

    if vim.startswith(line, "@@ ") then
      local index = string.find(line, "@[^@]*$")
      local content_highlight = get_content_highlight("DiffLine", i)
      local vt_line = {
        { "│" },
        { string.rep(" ", 2 * max_lnum + 1), "DiffLine" },
        { string.sub(line, 0, index), "DiffLine" },
      }
      vim.list_extend(vt_line, content_highlight)
      vim.list_extend(vt_line, {
        { string.rep(" ", 1 + max_length - vim.fn.strdisplaywidth(line) - 2 * max_lnum), "DiffLine" },
        { "│" },
      })
      table.insert(vt_lines, vt_line)
    elseif vim.startswith(line, "+") then
      local vt_line = { { "│" } }
      vim.list_extend(vt_line, get_lnum_chunks { right_line = map.right_side_lines[i], max_lnum = max_lnum })
      vim.list_extend(vt_line, get_content_highlight("DiffAdd", i))
      vim.list_extend(vt_line, {
        { string.rep(" ", max_length - vim.fn.strdisplaywidth(line) - 2 * max_lnum), "DiffAdd" },
        { "│" },
      })
      table.insert(vt_lines, vt_line)
    elseif vim.startswith(line, "-") then
      local vt_line = { { "│" } }
      vim.list_extend(vt_line, get_lnum_chunks { left_line = map.left_side_lines[i], max_lnum = max_lnum })
      vim.list_extend(vt_line, get_content_highlight("DiffDelete", i))
      vim.list_extend(vt_line, {
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
      vim.list_extend(vt_line, get_content_highlight(nil, i))
      vim.list_extend(vt_line, {
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

---@param bufnr integer
---@param reactions table<string, string[]>
function M.write_reactions_summary(bufnr, reactions)
  local lines = {} ---@type string[]
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

---@param max_length integer
---@param chunk [string, string][]
local function chunk_length(max_length, chunk)
  local length = 0
  for _, c in ipairs(chunk) do
    length = length + vim.fn.strdisplaywidth(c[1])
  end
  return math.max(max_length, length)
end

--- Write a user profile to the given buffer as virtual text.
---@param bufnr integer
---@param user octo.UserProfile
---@param opts? { max_width?: integer }
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

---@param bufnr integer
---@param discussion octo.DiscussionSummary
---@param opts? { max_length?: integer }
---@return integer
function M.write_discussion_summary(bufnr, discussion, opts)
  opts = opts or {}
  local conf = config.values
  local max_length = opts.max_length or 80
  local chunks = {} ---@type [string, string][][]

  -- repo and date line
  table.insert(chunks, {
    { " " },
    { discussion.repository.nameWithOwner, "OctoDetailsValue" },
    { " " .. utils.format_date(discussion.createdAt), "OctoDetailsValue" },
  })

  -- discussion overview
  local state = discussion.closed and "CLOSED" or "OPEN"
  table.insert(chunks, {
    { " " },
    { "[" .. state:gsub("_", " ") .. "] ", utils.state_hl_map[state] },
    { discussion.title .. " ", "OctoDetailsLabel" },
    { "#" .. discussion.number .. " ", "OctoDetailsValue" },
  })
  if not utils.is_blank(discussion.isAnswered) and discussion.isAnswered then
    table.insert(chunks, { { " " }, { "✓ Answered", "OctoStateApproved" } })
  end
  table.insert(chunks, { { "" } })

  -- discussion body
  local body_lines = vim.split(discussion.body, "\n")
  local body = table.concat(body_lines, " ")
  body = body:gsub("[%c]", " ")
  body = body:sub(1, max_length - 4 - 2) .. "…"
  table.insert(chunks, {
    { " " },
    { body },
  })
  table.insert(chunks, { { "" } })

  -- labels
  if #discussion.labels.nodes > 0 then
    local labels = {}
    for _, label in ipairs(discussion.labels.nodes) do
      local label_bubble = bubbles.make_label_bubble(label.name, label.color, { right_margin_width = 1 })
      vim.list_extend(labels, label_bubble)
    end
    table.insert(chunks, labels)
    table.insert(chunks, { { "" } })
  end

  -- author line
  if utils.is_blank(discussion.author) then
    table.insert(chunks, {
      { " " },
      { conf.ghost_icon or "󰊠 " },
      { "ghost" },
    })
  else
    table.insert(chunks, {
      { " " },
      { conf.user_icon or " " },
      { discussion.author.login },
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

---@param bufnr integer
---@param issue octo.IssueOrPullRequestSummary
---@param opts? { max_length?: integer }
function M.write_issue_summary(bufnr, issue, opts)
  opts = opts or {}
  local max_length = opts.max_length or 80
  local chunks = {}

  -- repo and date line
  table.insert(chunks, {
    { " " },
    { issue.repository.nameWithOwner, "OctoDetailsValue" },
    { " " .. utils.format_date(issue.createdAt), "OctoDetailsValue" },
  })

  -- issue title with state
  local state = utils.get_displayed_state(issue.__typename == "Issue", issue.state, issue.stateReason)
  local is_issue = issue.__typename == "Issue"
  local title_line = TextChunkBuilder:new()
    :text(" ")
    :state_with_icon(state, issue.stateReason, issue.isDraft, function(s, sr)
      return get_state_icon(s, sr, is_issue, false)
    end)
    :text(" " .. issue.title .. " ", "OctoDetailsLabel")
    :text("#" .. issue.number .. " ", "OctoDetailsValue")
    :build()
  table.insert(chunks, title_line)
  table.insert(chunks, { { "" } })

  -- issue body
  local body_lines = vim.split(issue.body, "\n")
  local body = table.concat(body_lines, " ")
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
  issue.author = logins.format_author(issue.author)
  table.insert(chunks, {
    { " " },
    { logins.get_user_icon(issue.author.login) },
    { issue.author.login },
  })

  for i = 1, #chunks do
    M.write_block(bufnr, { "" }, i)
  end
  for i = 1, #chunks do
    M.write_virtual_text(bufnr, constants.OCTO_SUMMARY_VT_NS, i - 1, chunks[i])
  end
  return #chunks
end

--- Helper to write an event virtual text with proper spacing.
---@param bufnr integer
---@param vt [string, string][]
local function write_event(bufnr, vt)
  local line = vim.api.nvim_buf_line_count(bufnr) - 1
  M.write_block(bufnr, { "" }, line + 2)
  M.write_virtual_text(bufnr, constants.OCTO_EVENT_VT_NS, line + 1, vt)
end

---@param statusCheckRollup { state: octo.StatusState }
---@return string[]
local function get_status_check(statusCheckRollup)
  if utils.is_blank(statusCheckRollup) then
    return { "  " }
  end

  local state = statusCheckRollup.state
  local state_info = utils.state_map[state]

  return { state_info.symbol, state_info.hl }
end

---@param bufnr integer
---@param item octo.fragments.PullRequestCommit
---@param include_date boolean
local function write_commit(bufnr, item, include_date)
  local status_check = get_status_check(item.commit.statusCheckRollup)
  local builder = TextChunkBuilder:new()
    :timeline_marker("commit")
    :extend({ status_check })
    :text(item.commit.abbreviatedOid, "OctoDetailsLabel")
    :space()
    :text(item.commit.messageHeadline, "OctoDetailsLabel")

  if include_date then
    builder = builder:date(item.commit.committedDate)
  end

  builder:write_event(bufnr)
end

---@param bufnr integer
---@param commits octo.fragments.PullRequestCommit[]
local function write_commit_header(bufnr, commits)
  ---@param item octo.fragments.PullRequestCommit
  local function get_author(item)
    if item.commit.committer.user ~= vim.NIL then
      return item.commit.committer.user.login
    elseif item.commit.author ~= vim.NIL and item.commit.author.user ~= vim.NIL then
      return item.commit.author.user.login
    end
    return "ghost"
  end
  local authors = {} ---@type table<string,boolean>
  for _, item in ipairs(commits) do
    authors[get_author(item)] = true
  end
  local n_authors = vim.tbl_count(authors)
  local num_commits = #commits

  local first_item = commits[1]
  local first_user = get_author(first_item)

  TextChunkBuilder:new()
    :timeline_marker("commit_push")
    :user_plain(first_user, first_user == vim.g.octo_viewer)
    :when(
      n_authors > 1,
      " and " .. n_authors - 1 .. " other" .. (n_authors > 2 and "s" or ""),
      "OctoTimelineItemHeading"
    )
    :heading(" added ")
    :heading(num_commits .. " commit" .. (num_commits > 1 and "s" or ""))
    :date(first_item.commit.committedDate)
    :write_event(bufnr)
end

---@param bufnr integer
---@param commits octo.fragments.PullRequestCommit[]
function M.write_commits(bufnr, commits)
  local include_date = #commits == 1
  if #commits ~= 1 then
    write_commit_header(bufnr, commits)
  end
  for _, item in ipairs(commits) do
    write_commit(bufnr, item, include_date)
  end
end

---@param bufnr integer
---@param item octo.fragments.ProjectV2ItemStatusChangedEvent
function M.write_project_v2_item_status_changed_event(bufnr, item)
  -- Skip rendering if project is nil - GitHub API returns empty events
  -- These new event types (added Nov 2025) sometimes return with all fields nil
  if not item.project then
    warn_projects_v2_config()
    return
  end

  local conf = config.values
  item.actor = logins.format_author(item.actor)

  local builder = TextChunkBuilder:new():timeline_marker("project"):actor(item.actor):heading " moved this "

  if item.previousStatus ~= "" and item.status ~= "" then
    builder
      :heading("from ")
      :text(item.previousStatus, "OctoDetailsLabel")
      :heading(" to ")
      :text(item.status, "OctoDetailsLabel")
      :heading(" in " .. conf.timeline_icons.project)
      :text(item.project.title, "OctoDetailsLabel")
  elseif item.status ~= "" then
    builder
      :heading("to ")
      :text(item.status, "OctoDetailsLabel")
      :heading(" in " .. conf.timeline_icons.project)
      :text(item.project.title, "OctoDetailsLabel")
  else
    builder
      :heading("from ")
      :text(item.previousStatus, "OctoDetailsLabel")
      :heading(" to ")
      :text("No Status", "OctoDetailsLabel")
      :heading(" in " .. conf.timeline_icons.project)
      :text(item.project.title, "OctoDetailsLabel")
  end

  builder:date(item.createdAt):write_event(bufnr)
end

local write_project_v2_event = function(bufnr, item, verb)
  -- Skip rendering if project is nil - GitHub API returns empty events
  -- These new event types (added Nov 2025) sometimes return with all fields nil
  if not item.project then
    warn_projects_v2_config()
    return
  end

  local conf = config.values
  item.actor = logins.format_author(item.actor)

  TextChunkBuilder:new()
    :timeline_marker("project")
    :actor(item.actor)
    :heading(" " .. verb .. " this to " .. conf.timeline_icons.project)
    :text(item.project.title, "OctoDetailsLabel")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.AddedToProjectV2Event
function M.write_added_to_project_v2_event(bufnr, item)
  write_project_v2_event(bufnr, item, "added")
end

---@param bufnr integer
---@param item octo.fragments.RemovedFromProjectV2Event
function M.write_removed_from_project_v2_event(bufnr, item)
  write_project_v2_event(bufnr, item, "removed")
end

---@param bufnr integer
---@param item octo.fragments.AutoSquashEnabledEvent
function M.write_auto_squash_enabled_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("auto_squash")
    :actor(item.actor)
    :heading(" enabled auto-merge (squash)")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.HeadRefDeletedEvent
function M.write_head_ref_deleted_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("head_ref")
    :actor(item.actor)
    :heading(" deleted the ")
    :text(item.headRefName, "OctoDetailsLabel")
    :heading(" branch")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.CommentDeletedEvent
function M.write_comment_deleted_event(bufnr, item)
  item.actor = logins.format_author(item.actor)
  item.deletedCommentAuthor = logins.format_author(item.deletedCommentAuthor)
  TextChunkBuilder:new()
    :timeline_marker("comment_deleted")
    :actor(item.actor)
    :heading(" deleted a comment from ")
    :actor(item.deletedCommentAuthor)
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.TransferredEvent
function M.write_transferred_event(bufnr, item)
  item.actor = logins.format_author(item.actor)
  TextChunkBuilder:new()
    :timeline_marker("transferred")
    :actor(item.actor)
    :heading(" transferred this issue from ")
    :text(item.fromRepository.nameWithOwner, "OctoDetailsLabel")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.HeadRefRestoredEvent
function M.write_head_ref_restored_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("head_ref")
    :actor(item.actor)
    :heading(" restored the ")
    :text(item.pullRequest.headRefName, "OctoDetailsLabel")
    :heading(" branch")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param items octo.fragments.HeadRefForcePushedEvent[]
function M.write_head_ref_force_pushed_events(bufnr, items)
  local total_events = #items
  local builder = TextChunkBuilder:new()
    :timeline_marker("force_push")
    :actor(items[1].actor)
    :heading(" force-pushed the ")
    :text(items[1].pullRequest.headRefName, "OctoDetailsLabel")

  if total_events > 1 then
    builder
      :heading(" branch " .. tostring(total_events) .. " times, most recently from ")
      :text(items[total_events].beforeCommit.abbreviatedOid, "OctoDetailsValue")
      :heading(" to ")
      :text(items[total_events].afterCommit.abbreviatedOid, "OctoDetailsValue")
      :date(items[total_events].createdAt)
  else
    builder
      :heading(" branch from ")
      :text(items[1].beforeCommit.abbreviatedOid, "OctoDetailsValue")
      :heading(" to ")
      :text(items[1].afterCommit.abbreviatedOid, "OctoDetailsValue")
      :date(items[1].createdAt)
  end

  builder:write_event(bufnr)
end

---Build assignment event text builders
---@param items (octo.fragments.AssignedEvent|octo.fragments.UnassignedEvent)[]
---@param viewer string Current viewer login
---@return TextChunkBuilder[] Array of builders, one per actor
function M.build_assignment_event_chunks(items, viewer)
  ---@class ActorEvents
  ---@field assigned table<string, integer>
  ---@field unassigned table<string, integer>
  ---@field timestamp string

  ---@type table<string, ActorEvents>
  local events_by_actor = {}

  for _, item in ipairs(items) do
    local actor_login = item.actor ~= vim.NIL and item.actor.login or vim.NIL
    if actor_login ~= vim.NIL then
      ---@cast actor_login string
      if not events_by_actor[actor_login] then
        events_by_actor[actor_login] = { assigned = {}, unassigned = {}, timestamp = item.createdAt }
      end
      local assignee_name = item.assignee.login or item.assignee.name
      if item.__typename == "AssignedEvent" then
        events_by_actor[actor_login].assigned[assignee_name] = (
          events_by_actor[actor_login].assigned[assignee_name] or 0
        ) + 1
      elseif item.__typename == "UnassignedEvent" then
        events_by_actor[actor_login].unassigned[assignee_name] = (
          events_by_actor[actor_login].unassigned[assignee_name] or 0
        ) + 1
      end
      -- Track earliest timestamp for this actor
      if item.createdAt < events_by_actor[actor_login].timestamp then
        events_by_actor[actor_login].timestamp = item.createdAt
      end
    end
  end

  ---@type TextChunkBuilder[]
  local results = {}
  for actor, events in pairs(events_by_actor) do
    ---@type string[]
    local assigned_list = {}
    for assignee, _ in pairs(events.assigned) do
      table.insert(assigned_list, assignee)
    end
    ---@type string[]
    local unassigned_list = {}
    for assignee, _ in pairs(events.unassigned) do
      table.insert(unassigned_list, assignee)
    end

    local has_assigned = #assigned_list > 0
    local has_unassigned = #unassigned_list > 0
    local is_self_only_assigned = has_assigned and #assigned_list == 1 and assigned_list[1] == actor
    local is_self_only_unassigned = has_unassigned and #unassigned_list == 1 and unassigned_list[1] == actor

    local builder = TextChunkBuilder:new():timeline_marker("assigned"):user_plain(actor, actor == viewer)

    if is_self_only_assigned and not has_unassigned then
      builder:heading " self-assigned this"
    elseif is_self_only_unassigned and not has_assigned then
      builder:heading " removed their assignment"
    else
      if has_assigned then
        builder:heading " assigned "
        for i, assignee in ipairs(assigned_list) do
          if i > 1 then
            builder:heading ", "
          end
          builder:user_plain(assignee, assignee == viewer)
        end
      end

      if has_assigned and has_unassigned then
        builder:heading " and"
      end

      if has_unassigned then
        builder:heading " unassigned "
        for i, assignee in ipairs(unassigned_list) do
          if i > 1 then
            builder:heading ", "
          end
          builder:user_plain(assignee, assignee == viewer)
        end
      end
    end

    builder:date(events.timestamp)
    table.insert(results, builder)
  end

  return results
end

---@param bufnr integer
---@param items (octo.fragments.AssignedEvent|octo.fragments.UnassignedEvent)[]
function M.write_assignment_events(bufnr, items)
  -- Format authors first
  for _, item in ipairs(items) do
    item.actor = logins.format_author(item.actor)
    item.assignee = logins.format_author(item.assignee)
  end

  local builders = M.build_assignment_event_chunks(items, vim.g.octo_viewer)

  for _, builder in ipairs(builders) do
    builder:write_event(bufnr)
  end
end

---@param bufnr integer
---@param item octo.fragments.PullRequest|octo.fragments.Issue
---@param spaces? integer
---@param include_repo? boolean
local function write_issue_or_pr(bufnr, item, spaces, include_repo)
  spaces = spaces or 10
  include_repo = include_repo or false
  local vt = {}
  local state = utils.get_displayed_state(item.__typename == "Issue", item.state, item.stateReason, item.isDraft)
  local entry = {
    kind = item.__typename == "Issue" and "issue" or "pull_request",
    obj = item,
  }
  local icon = utils.get_icon(entry)
  table.insert(vt, { string.rep(" ", spaces), "OctoTimelineItemHeading" })
  table.insert(vt, { item.title, "OctoDetailsLabel" })
  if include_repo then
    table.insert(
      vt,
      { " " .. item.repository.nameWithOwner .. "#" .. tostring(item.number) .. " ", "OctoDetailsValue" }
    )
  else
    table.insert(vt, { " #" .. tostring(item.number) .. " ", "OctoDetailsValue" })
  end
  table.insert(vt, icon)
  table.insert(vt, { state, utils.state_hl_map[state] })

  write_event(bufnr, vt)
end

local function write_reference_commit(bufnr, commit)
  local spaces = config.values.use_timeline_icons and 3 or 10
  TextChunkBuilder:new()
    :space(spaces)
    :text(commit.message, "OctoTimelineItemHeading")
    :space()
    :text(commit.abbreviatedOid, "OctoTimelineItemHeading")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.DeployedEvent
function M.write_deployed_event(bufnr, item)
  local bubble_info = utils.deployed_state_map[item.deployment.state]
  TextChunkBuilder:new()
    :timeline_marker("deployed")
    :actor(item.actor)
    :heading(" deployed to ")
    :text(item.deployment.environment, "OctoDetailsLabel")
    :date(item.createdAt, " ")
    :space()
    :bubble(bubble_info[1], bubble_info[2])
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.ReferencedEvent
function M.write_referenced_event(bufnr, item)
  if utils.is_blank(item.actor) then
    return
  end

  TextChunkBuilder:new()
    :timeline_marker("reference")
    :actor(item.actor)
    :heading(" added a commit to ")
    :text(item.commit.repository.nameWithOwner, "OctoDetailsLabel")
    :heading(" that referenced this issue ")
    :date(item.createdAt, "")
    :write_event(bufnr)
  write_reference_commit(bufnr, item.commit)
end

---@param bufnr integer
---@param items (octo.fragments.SubIssueAddedEvent|octo.fragments.SubIssueRemovedEvent)[]
---@param action "added"|"removed"
function M.write_subissue_events(bufnr, items, action)
  local previous_actor = ""
  for i, item in ipairs(items) do
    local conf = config.values
    local spaces = conf.use_timeline_icons and 3 or 10
    if item.actor.login ~= previous_actor then
      local next_actor = items[i + 1] and items[i + 1].actor and items[i + 1].actor.login or ""
      local plural = next_actor == item.actor.login
      TextChunkBuilder:new()
        :timeline_marker("subissue")
        :actor(item.actor)
        :heading(plural and (" " .. action .. " sub-issues ") or (" " .. action .. " a sub-issue "))
        :date(item.createdAt)
        :write_event(bufnr)
    end
    local subIssue = item.subIssue
    subIssue.__typename = "Issue"
    write_issue_or_pr(bufnr, subIssue, spaces)

    previous_actor = item.actor.login
  end
end

---@param bufnr integer
---@param item octo.fragments.BlockedByAddedEvent|octo.fragments.BlockedByRemovedEvent
local function write_blocked_by_event(bufnr, item, verb)
  TextChunkBuilder:new()
    :timeline_marker("blocking")
    :actor(item.actor)
    :space()
    :heading(verb .. " this as blocked by")
    :date(item.createdAt)
    :write_event(bufnr)
  local conf = config.values
  local spaces = conf.use_timeline_icons and 3 or 10
  write_issue_or_pr(bufnr, item.blockingIssue, spaces)
end

---@param bufnr integer
---@param item octo.fragments.BlockedByAddedEvent
function M.write_blocked_by_added_event(bufnr, item)
  write_blocked_by_event(bufnr, item, "marked")
end

---@param bufnr integer
---@param item octo.fragments.BlockedByRemovedEvent
function M.write_blocked_by_removed_event(bufnr, item)
  write_blocked_by_event(bufnr, item, "unmarked")
end

---@param bufnr integer
---@param item octo.fragments.BlockingAddedEvent|octo.fragments.BlockingRemovedEvent
local function write_blocking_event(bufnr, item, verb)
  TextChunkBuilder:new()
    :timeline_marker("blocking")
    :actor(item.actor)
    :space()
    :heading(verb .. " this as blocking")
    :date(item.createdAt)
    :write_event(bufnr)
  local conf = config.values
  local spaces = conf.use_timeline_icons and 3 or 10
  write_issue_or_pr(bufnr, item.blockedIssue, spaces)
end

---@param bufnr integer
---@param item octo.fragments.BlockingAddedEvent
function M.write_blocking_added_event(bufnr, item)
  write_blocking_event(bufnr, item, "marked")
end

---@param bufnr integer
---@param item octo.fragments.BlockingRemovedEvent
function M.write_blocking_removed_event(bufnr, item)
  write_blocking_event(bufnr, item, "unmarked")
end

---@param bufnr integer
---@param item octo.fragments.CrossReferencedEvent
function M.write_cross_referenced_event(bufnr, item)
  local conf = config.values
  local spaces = conf.use_timeline_icons and 3 or 10
  item.actor = logins.format_author(item.actor)

  local target = item.target
  local will_close_target = item.willCloseTarget
  local is_pr = target.__typename == "PullRequest"

  local builder = TextChunkBuilder:new():timeline_marker("cross_reference"):actor(item.actor)

  if is_pr and not will_close_target then
    builder:heading(" mentioned this pull request "):date(item.createdAt, "")
  elseif is_pr then
    builder:heading(" linked a pull request "):date(item.createdAt, ""):heading " that will close this issue "
  elseif not will_close_target then
    builder:heading(" mentioned this issue "):date(item.createdAt, "")
  else
    builder:heading(" linked an issue "):date(item.createdAt, ""):heading " that may be closed by this pull request "
  end

  builder:write_event(bufnr)
  write_issue_or_pr(bufnr, item.source, spaces, item.isCrossRepository)
end

---@param bufnr integer
---@param item octo.fragments.ParentIssueAddedEvent|octo.fragments.ParentIssueRemovedEvent
---@param add boolean
local function write_parent_issue_event(bufnr, item, add)
  local verb = add and "added" or "removed"
  local conf = config.values
  local spaces = conf.use_timeline_icons and 3 or 10

  TextChunkBuilder:new()
    :timeline_marker("parent_issue")
    :actor(item.actor)
    :heading(" " .. verb .. " a parent issue ")
    :date(item.createdAt, "")
    :write_event(bufnr)
  local parent = item.parent
  parent.__typename = "Issue"
  write_issue_or_pr(bufnr, parent, spaces)
end

---@param bufnr integer
---@param item octo.fragments.ParentIssueAddedEvent
function M.write_parent_issue_added_event(bufnr, item)
  write_parent_issue_event(bufnr, item, true)
end

---@param bufnr integer
---@param item octo.fragments.ParentIssueRemovedEvent
function M.write_parent_issue_removed_event(bufnr, item)
  write_parent_issue_event(bufnr, item, false)
end

---@param bufnr integer
---@param item octo.fragments.IssueTypeAddedEvent|octo.fragments.IssueTypeRemovedEvent
---@param add boolean
local function write_issue_type_event(bufnr, item, add)
  local verb = add and "added" or "removed"
  local label_bubble = bubbles.make_label_bubble(item.issueType.name, item.issueType.color)
  TextChunkBuilder:new()
    :timeline_marker("issue_type")
    :actor(item.actor)
    :heading(" " .. verb .. " the ")
    :extend(label_bubble)
    :heading(" issue type ")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.IssueTypeAddedEvent
function M.write_issue_type_added_event(bufnr, item)
  write_issue_type_event(bufnr, item, true)
end

---@param bufnr integer
---@param item octo.fragments.IssueTypeRemovedEvent
function M.write_issue_type_removed_event(bufnr, item)
  write_issue_type_event(bufnr, item, false)
end

---@param bufnr integer
---@param item octo.fragments.IssueTypeChangedEvent
function M.write_issue_type_changed_event(bufnr, item)
  local prev_bubble = bubbles.make_label_bubble(item.prevIssueType.name, item.prevIssueType.color)
  local new_bubble = bubbles.make_label_bubble(item.issueType.name, item.issueType.color)
  TextChunkBuilder:new()
    :timeline_marker("issue_type")
    :actor(item.actor)
    :heading(" changed the issue type from ")
    :extend(prev_bubble)
    :heading(" to ")
    :extend(new_bubble)
    :space()
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.ConvertToDraftEvent
function M.write_convert_to_draft_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("draft")
    :actor(item.actor)
    :heading(" marked this pull request as draft ")
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.AutomaticBaseChangeSucceededEvent
function M.write_automatic_base_change_succeeded_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("automatic_base_change_succeeded", "OctoStateSubmitted")
    :heading("Base automatically changed from ")
    :text(item.oldBase, "OctoDetailsLabel")
    :heading(" to ")
    :text(item.newBase, "OctoDetailsLabel")
    :space()
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.BaseRefChangedEvent
function M.write_base_ref_changed_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("base_ref_changed")
    :actor(item.actor)
    :heading(" changed the base branch from ")
    :text(item.previousRefName, "OctoDetailsLabel")
    :heading(" to ")
    :text(item.currentRefName, "OctoDetailsLabel")
    :space()
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.ReadyForReviewEvent
function M.write_ready_for_review_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("draft")
    :actor(item.actor)
    :heading(" marked this pull request as ready for review ")
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.PinnedEvent|octo.fragments.UnpinnedEvent
---@param add boolean
local function write_pinned_event(bufnr, item, add)
  local verb = add and "pinned" or "unpinned"

  TextChunkBuilder:new()
    :timeline_marker("pinned")
    :actor(item.actor)
    :heading(" " .. verb .. " this issue ")
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.PinnedEvent
function M.write_pinned_event(bufnr, item)
  write_pinned_event(bufnr, item, true)
end

---@param bufnr integer
---@param item octo.fragments.UnpinnedEvent
function M.write_unpinned_event(bufnr, item)
  write_pinned_event(bufnr, item, false)
end

---@param bufnr integer
---@param item octo.fragments.MilestonedEvent|octo.fragments.DemilestonedEvent
---@param add boolean
local function write_milestone_event(bufnr, item, add)
  local verb = add and "added" or "removed"
  local preposition = add and "to" or "from"

  TextChunkBuilder:new()
    :timeline_marker("milestone")
    :actor(item.actor)
    :heading(" " .. verb .. " this " .. preposition .. " the ")
    :text(item.milestoneTitle, "OctoDetailsLabel")
    :heading(" milestone ")
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.MilestonedEvent
function M.write_milestoned_event(bufnr, item)
  write_milestone_event(bufnr, item, true)
end

---@param bufnr integer
---@param item octo.fragments.DemilestonedEvent
function M.write_demilestoned_event(bufnr, item)
  write_milestone_event(bufnr, item, false)
end

---@param bufnr integer
---@param item octo.fragments.ConnectedEvent
function M.write_connected_event(bufnr, item)
  local conf = config.values
  local spaces = conf.use_timeline_icons and 3 or 10
  local subject = item.subject

  local builder = TextChunkBuilder:new():timeline_marker("connected"):actor(item.actor)

  if subject.__typename == "PullRequest" then
    builder:heading(" linked a pull request "):date(item.createdAt, ""):heading " that will close this issue "
  else
    builder:heading(" linked an issue "):date(item.createdAt, ""):heading " that may be closed by this pull request "
  end

  builder:write_event(bufnr)
  write_issue_or_pr(bufnr, item.subject, spaces)
end

---@param bufnr integer
---@param item octo.fragments.RenamedTitleEvent
function M.write_renamed_title_event(bufnr, item)
  local conf = config.values

  if utils.is_blank(item.actor) then
    TextChunkBuilder:new():timeline_marker("renamed"):heading("Title renamed"):write_event(bufnr)
    return
  end

  item.actor = logins.format_author(item.actor)
  TextChunkBuilder:new()
    :timeline_marker("renamed")
    :actor(item.actor)
    :heading(" changed the title ")
    :text(item.previousTitle, "OctoStrikethrough")
    :space()
    :text(item.currentTitle, "OctoDetailsLabel")
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.MergedEvent
function M.write_merged_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker("merged")
    :actor(item.actor)
    :heading(" merged commit ")
    :text(item.commit.abbreviatedOid, "OctoDetailsLabel")
    :heading(" into ")
    :heading(item.mergeRefName)
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.ClosedEvent
function M.write_closed_event(bufnr, item)
  local state = item.closable.state
  --- MERGED PRs have a MergedEvent already displayed
  if state == "MERGED" then
    return
  end
  local stateReason = item.closable and item.closable.stateReason or item.stateReason
  stateReason = utils.is_blank(stateReason) and item.stateReason or stateReason

  local lookup_value = item.closable and item.closable.__typename == "Issue" and stateReason or state
  lookup_value = string.lower(lookup_value)
  local conf = config.values

  local builder = TextChunkBuilder:new()
  if conf.use_timeline_icons then
    ---@type table
    local icon = conf.timeline_icons.closed[lookup_value] or conf.timeline_icons.closed.closed
    builder:text(icon[1], icon[2])
  else
    builder:timeline_marker()
  end

  builder
    :actor(item.actor)
    :when_fn(item.closable and item.closable.__typename == "Issue", function(b)
      return b:heading(" closed this as "):text(string.gsub(string.lower(stateReason), "_", " "), "OctoUnderline")
    end)
    :when(not (item.closable and item.closable.__typename == "Issue"), " closed this", "OctoTimelineItemHeading")
    :date(item.createdAt)
    :write_event(bufnr)
end

---Build label event text builders, combining labeled and unlabeled events per actor
---@param items (octo.fragments.LabeledEvent|octo.fragments.UnlabeledEvent)[]
---@param viewer string Current viewer login
---@return TextChunkBuilder[] Array of builders, one per actor
function M.build_label_event_chunks(items, viewer)
  ---@class ActorLabelEvents
  ---@field added table<string, octo.fragments.Label>
  ---@field removed table<string, octo.fragments.Label>
  ---@field timestamp string

  ---@type table<string, ActorLabelEvents>
  local events_by_actor = {}

  for _, item in ipairs(items) do
    local actor_login = item.actor ~= vim.NIL and item.actor.login or vim.NIL
    if actor_login ~= vim.NIL then
      ---@cast actor_login string
      if not events_by_actor[actor_login] then
        events_by_actor[actor_login] = { added = {}, removed = {}, timestamp = item.createdAt }
      end
      -- Use label name as key to automatically deduplicate
      if item.__typename == "LabeledEvent" then
        events_by_actor[actor_login].added[item.label.name] = item.label
      elseif item.__typename == "UnlabeledEvent" then
        events_by_actor[actor_login].removed[item.label.name] = item.label
      end
      -- Track earliest timestamp for this actor
      if item.createdAt < events_by_actor[actor_login].timestamp then
        events_by_actor[actor_login].timestamp = item.createdAt
      end
    end
  end

  ---@type TextChunkBuilder[]
  local results = {}
  for actor, events in pairs(events_by_actor) do
    ---@type octo.fragments.Label[]
    local added_list = {}
    for _, label in pairs(events.added) do
      table.insert(added_list, label)
    end
    ---@type octo.fragments.Label[]
    local removed_list = {}
    for _, label in pairs(events.removed) do
      table.insert(removed_list, label)
    end

    local has_added = #added_list > 0
    local has_removed = #removed_list > 0

    local builder = TextChunkBuilder:new():timeline_marker("label"):user_plain(actor, actor == viewer)

    if has_added then
      builder:heading " added "
      for i, label in ipairs(added_list) do
        local is_last = i == #added_list
        local label_bubble =
          bubbles.make_label_bubble(label.name, label.color, { right_margin_width = is_last and 0 or 1 })
        builder:extend(label_bubble)
      end
    end

    if has_added and has_removed then
      builder:heading " and"
    end

    if has_removed then
      builder:heading " removed "
      for i, label in ipairs(removed_list) do
        local is_last = i == #removed_list
        local label_bubble =
          bubbles.make_label_bubble(label.name, label.color, { right_margin_width = is_last and 0 or 1 })
        builder:extend(label_bubble)
      end
    end

    builder:date(events.timestamp)
    table.insert(results, builder)
  end

  return results
end

---@param bufnr integer
---@param items (octo.fragments.LabeledEvent|octo.fragments.UnlabeledEvent)[]
function M.write_label_events(bufnr, items)
  -- Format authors first
  for _, item in ipairs(items) do
    item.actor = logins.format_author(item.actor)
  end

  local builders = M.build_label_event_chunks(items, vim.g.octo_viewer)

  for _, builder in ipairs(builders) do
    builder:write_event(bufnr)
  end
end

---@param bufnr integer
---@param item octo.fragments.ReopenedEvent
function M.write_reopened_event(bufnr, item)
  item.actor = logins.format_author(item.actor)
  TextChunkBuilder:new()
    :timeline_marker("reopened")
    :actor(item.actor)
    :heading(" reopened this ")
    :date(item.createdAt, "")
    :write_event(bufnr)
end

---Assumes all events are from the same time and from the same actor
---@param bufnr integer
---@param items octo.fragments.ReviewRequestedEvent[]
function M.write_review_requested_events(bufnr, items)
  items[1].actor = logins.format_author(items[1].actor)
  local builder =
    TextChunkBuilder:new():timeline_marker("review_requested"):actor(items[1].actor):heading " requested a review"

  local found_reviewer = false
  for _, item in ipairs(items) do
    if item.requestedReviewer ~= vim.NIL then
      builder:heading(found_reviewer and ", " or " from ")
      item.requestedReviewer = logins.format_author(item.requestedReviewer)
      local reviewer = item.requestedReviewer.login or item.requestedReviewer.name
      builder:user_plain(reviewer, reviewer == vim.g.octo_viewer)
      found_reviewer = true
    end
  end

  builder:date(items[1].createdAt):write_event(bufnr)
end

---@param bufnr integer
---@param items octo.fragments.ReviewRequestRemovedEvent[]
function M.write_review_request_removed_events(bufnr, items)
  local builder = TextChunkBuilder:new()
    :timeline_marker("review_requested")
    :actor(items[1].actor)
    :heading " removed a review request for "

  local found_reviewer = false
  for _, item in ipairs(items) do
    if item.requestedReviewer ~= vim.NIL then
      builder:when(found_reviewer, ", ", "OctoTimelineItemHeading")
      local reviewer = item.requestedReviewer.login or item.requestedReviewer.name or "unknown"
      builder:user_plain(reviewer, reviewer == vim.g.octo_viewer)
      found_reviewer = true
    end
  end

  builder:date(items[1].createdAt):write_event(bufnr)
end

---@param bufnr integer
---@param item octo.fragments.ReviewDismissedEvent
function M.write_review_dismissed_event(bufnr, item)
  TextChunkBuilder:new()
    :timeline_marker()
    :actor(item.actor)
    :heading(" dismissed a review")
    :when_fn(item.dismissalMessage ~= vim.NIL, function(b)
      return b:heading(" ["):text(item.dismissalMessage, "OctoUser"):heading "]"
    end)
    :date(item.createdAt)
    :write_event(bufnr)
end

---@param bufnr integer
---@param threads octo.ReviewThread[]
function M.write_threads(bufnr, threads)
  local comment_start, comment_end ---@type integer, integer

  -- print each of the threads
  for _, thread in ipairs(threads) do
    local thread_start, thread_end ---@type integer, integer
    for _, comment in ipairs(thread.comments.nodes) do
      ---@class octo.AugmentedReviewThreadComment : octo.ReviewThreadCommentFragment
      ---@field diffSide string
      ---@field start_line integer
      ---@field end_line integer
      comment = comment
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
        local diffhunk_lang ---@type string|nil
        -- Filetype detection doesn't quite work sometimes: https://github.com/neovim/neovim/issues/27265
        local temp_bufnr = vim.api.nvim_create_buf(false, true)
        local filetype = vim.filetype.match { filename = comment.path, buf = temp_bufnr }
        if filetype ~= nil then
          diffhunk_lang = vim.treesitter.language.get_lang(filetype)
        end

        -- write snippet
        thread_start, thread_end =
          M.write_thread_snippet(bufnr, comment.diffHunk, diffhunk_lang, nil, start_line, end_line, thread.diffSide)
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

--- Write virtual text at a specific line in a buffer
---@param bufnr integer The buffer number
---@param ns integer The namespace id
---@param line integer The line number
---@param chunks [string, string][] The virtual text chunks
function M.write_virtual_text(bufnr, ns, line, chunks)
  pcall(
    vim.api.nvim_buf_set_extmark,
    bufnr,
    ns,
    line,
    0,
    { virt_text = chunks, virt_text_pos = "overlay", hl_mode = "combine" }
  )
end

---@param obj any
---@param bufnr integer
function M.discussion_preview(obj, bufnr)
  -- clear the buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  local state = obj.closed and "CLOSED" or "OPEN"
  M.write_title(bufnr, tostring(obj.title), 1)
  M.write_state(bufnr, state, obj.number)
  M.write_discussion_details(bufnr, obj)
  M.write_body(bufnr, obj, 13)

  if obj.answer ~= vim.NIL then
    local line = vim.api.nvim_buf_line_count(bufnr) + 1
    M.write_discussion_answer(bufnr, obj, line)
  end

  vim.bo[bufnr].filetype = "octo"
end

---@param obj any
---@param bufnr integer
function M.issue_preview(obj, bufnr)
  M.write_title(bufnr, obj.title, 1)
  M.write_details(bufnr, obj, nil, true)
  M.write_body(bufnr, obj)
  local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
  M.write_block(bufnr, { "", "" }, reactions_line)
  M.write_reactions(bufnr, obj.reactionGroups, reactions_line)
  vim.bo[bufnr].filetype = "octo"
end

---@param obj octo.Release
---@param bufnr integer
function M.release_preview(obj, bufnr)
  M.write_release(bufnr, obj)
  vim.bo[bufnr].filetype = "octo"
end

---@type string[]
local non_rendering_events = { "UnsubscribedEvent", "SubscribedEvent", "MentionedEvent" }

---@param typename string
---@return boolean
local is_rendering_event = function(typename)
  for _, t in ipairs(non_rendering_events) do
    if t == typename then
      return false
    end
  end
  return true
end

---@param bufnr integer
---@param obj octo.PullRequest|octo.Issue
function M.write_timeline_items(bufnr, obj)
  local unrendered_label_events = {} ---@type (octo.fragments.LabeledEvent|octo.fragments.UnlabeledEvent)[]
  local unrendered_subissue_added_events = {} ---@type octo.fragments.SubIssueAddedEvent[]
  local unrendered_subissue_removed_events = {} ---@type octo.fragments.SubIssueRemovedEvent[]
  local unrendered_force_push_events = {} ---@type octo.fragments.HeadRefForcePushedEvent[]
  local commits = {} ---@type octo.fragments.PullRequestCommit[]
  local unrendered_review_requested_events = {} ---@type octo.fragments.ReviewRequestedEvent[]
  local unrendered_review_request_removed_events = {} ---@type octo.fragments.ReviewRequestRemovedEvent[]
  local unrendered_assignment_events = {} ---@type (octo.fragments.AssignedEvent|octo.fragments.UnassignedEvent)[]
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
    if
      #unrendered_label_events > 0
      and (not item or (item.__typename ~= "LabeledEvent" and item.__typename ~= "UnlabeledEvent"))
    then
      M.write_label_events(bufnr, unrendered_label_events)
      unrendered_label_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "SubIssueAddedEvent") and #unrendered_subissue_added_events > 0 then
      M.write_subissue_events(bufnr, unrendered_subissue_added_events, "added")
      unrendered_subissue_added_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "SubIssueRemovedEvent") and #unrendered_subissue_removed_events > 0 then
      M.write_subissue_events(bufnr, unrendered_subissue_removed_events, "removed")
      unrendered_subissue_removed_events = {}
      prev_is_event = true
    end
    if (not item or item.__typename ~= "PullRequestCommit") and #commits > 0 then
      M.write_commits(bufnr, commits)
      commits = {}
      prev_is_event = true
    end
    if
      #unrendered_force_push_events > 0
      and (
        not item
        or item.__typename ~= "HeadRefForcePushedEvent"
        or item.actor.login ~= unrendered_force_push_events[1].actor.login
      )
    then
      M.write_head_ref_force_pushed_events(bufnr, unrendered_force_push_events)
      unrendered_force_push_events = {}
      prev_is_event = true
    end
    if
      #unrendered_review_requested_events > 0
      and (
        not item
        or item.__typename ~= "ReviewRequestedEvent"
        or unrendered_review_requested_events[1].createdAt ~= item.createdAt
      )
    then
      M.write_review_requested_events(bufnr, unrendered_review_requested_events)
      unrendered_review_requested_events = {}
      prev_is_event = true
    end
    if
      #unrendered_review_request_removed_events > 0
      and (
        not item
        or item.__typename ~= "ReviewRequestRemovedEvent"
        or unrendered_review_request_removed_events[1].createdAt ~= item.createdAt
      )
    then
      M.write_review_request_removed_events(bufnr, unrendered_review_request_removed_events)
      unrendered_review_request_removed_events = {}
      prev_is_event = true
    end
    if
      #unrendered_assignment_events > 0
      and (not item or (item.__typename ~= "AssignedEvent" and item.__typename ~= "UnassignedEvent"))
    then
      M.write_assignment_events(bufnr, unrendered_assignment_events)
      unrendered_assignment_events = {}
      prev_is_event = true
    end
  end

  for _, item in ipairs(timeline_nodes) do
    render_accumulated_events(item)
    if item.__typename == "IssueComment" then
      if prev_is_event then
        M.write_block(bufnr, { "" })
      end

      -- write the comment
      local start_line, end_line = M.write_comment(bufnr, item, "IssueComment")
      folds.create(bufnr, start_line + 1, end_line, true)
      prev_is_event = false
    elseif item.__typename == "PullRequestReview" then
      if prev_is_event then
        M.write_block(bufnr, { "" })
      end

      -- A review can have 0+ threads
      local threads = {}
      for _, comment in ipairs(item.comments.nodes) do
        for _, reviewThread in ipairs(obj.reviewThreads.nodes) do
          if comment.id == reviewThread.comments.nodes[1].id then
            -- found a thread for the current review
            table.insert(threads, reviewThread)
          end
        end
      end

      -- skip reviews with no threads and empty body
      if #threads > 0 or not utils.is_blank(item.body) then
        -- print review header and top level comment
        local review_start, review_end = M.write_comment(bufnr, item, "PullRequestReview")

        -- print threads
        if #threads > 0 then
          review_end = M.write_threads(bufnr, threads)
          folds.create(bufnr, review_start + 1, review_end, true)
        end
        M.write_block(bufnr, { "" })
      else
        M.write_review_decision(bufnr, item)
      end
      prev_is_event = false
    elseif item.__typename == "AssignedEvent" then
      table.insert(unrendered_assignment_events, item)
    elseif item.__typename == "UnassignedEvent" then
      table.insert(unrendered_assignment_events, item)
    elseif item.__typename == "PullRequestCommit" then
      table.insert(commits, item)
      prev_is_event = true
    elseif item.__typename == "MergedEvent" then
      M.write_merged_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ClosedEvent" then
      M.write_closed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReopenedEvent" then
      M.write_reopened_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "LabeledEvent" then
      table.insert(unrendered_label_events, item)
    elseif item.__typename == "UnlabeledEvent" then
      table.insert(unrendered_label_events, item)
    elseif item.__typename == "ReviewRequestedEvent" then
      unrendered_review_requested_events[#unrendered_review_requested_events + 1] = item
      prev_is_event = true
    elseif item.__typename == "ReviewRequestRemovedEvent" then
      unrendered_review_request_removed_events[#unrendered_review_request_removed_events + 1] = item
      prev_is_event = true
    elseif item.__typename == "ReviewDismissedEvent" then
      M.write_review_dismissed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "RenamedTitleEvent" then
      M.write_renamed_title_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ConnectedEvent" then
      M.write_connected_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "CrossReferencedEvent" then
      M.write_cross_referenced_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReferencedEvent" then
      M.write_referenced_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "MilestonedEvent" then
      M.write_milestoned_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "DemilestonedEvent" then
      M.write_demilestoned_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "PinnedEvent" then
      M.write_pinned_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "UnpinnedEvent" then
      M.write_unpinned_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "SubIssueAddedEvent" then
      table.insert(unrendered_subissue_added_events, item)
    elseif item.__typename == "SubIssueRemovedEvent" then
      table.insert(unrendered_subissue_removed_events, item)
    elseif item.__typename == "ParentIssueAddedEvent" then
      M.write_parent_issue_added_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ParentIssueRemovedEvent" then
      M.write_parent_issue_removed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "IssueTypeAddedEvent" then
      M.write_issue_type_added_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "IssueTypeRemovedEvent" then
      M.write_issue_type_removed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "IssueTypeChangedEvent" then
      M.write_issue_type_changed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ConvertToDraftEvent" then
      M.write_convert_to_draft_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ReadyForReviewEvent" then
      M.write_ready_for_review_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "DeployedEvent" then
      M.write_deployed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "HeadRefDeletedEvent" then
      M.write_head_ref_deleted_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "HeadRefRestoredEvent" then
      M.write_head_ref_restored_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "HeadRefForcePushedEvent" then
      table.insert(unrendered_force_push_events, item)
    elseif item.__typename == "AutoSquashEnabledEvent" then
      M.write_auto_squash_enabled_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "AddedToProjectV2Event" then
      M.write_added_to_project_v2_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "RemovedFromProjectV2Event" then
      M.write_removed_from_project_v2_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "ProjectV2ItemStatusChangedEvent" then
      M.write_project_v2_item_status_changed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "AutomaticBaseChangeSucceededEvent" then
      M.write_automatic_base_change_succeeded_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "BaseRefChangedEvent" then
      M.write_base_ref_changed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "CommentDeletedEvent" then
      M.write_comment_deleted_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "BlockingAddedEvent" then
      M.write_blocking_added_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "BlockingRemovedEvent" then
      M.write_blocking_removed_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "BlockedByAddedEvent" then
      M.write_blocked_by_added_event(bufnr, item)
      prev_is_event = true
    elseif item.__typename == "BlockedByRemovedEvent" then
      M.write_blocked_by_removed_event(bufnr, item)
    elseif item.__typename == "TransferredEvent" then
      M.write_transferred_event(bufnr, item)
      prev_is_event = true
    elseif
      not utils.is_blank(item)
      and config.values.debug.notify_missing_timeline_items
      ---@diagnostic disable-next-line
      and is_rendering_event(item.__typename)
    then
      ---@diagnostic disable-next-line
      local info = item.__typename and item.__typename or vim.inspect(item)
      utils.info("Unhandled timeline item: " .. info)
    end
  end
  render_accumulated_events()

  if prev_is_event then
    M.write_block(bufnr, { "" })
  end
end

return M
