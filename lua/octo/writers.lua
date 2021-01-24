local hl = require "octo.highlights"
local constants = require "octo.constants"
local util = require "octo.util"
local vim = vim
local api = vim.api
local max = math.max
local min = math.min
local format = string.format

local M = {}

function M.write_block(lines, opts)
  local bufnr = opts.bufnr or api.nvim_get_current_buf()

  if type(lines) == "string" then
    lines = vim.split(lines, "\n", true)
  end

  local line = opts.line or api.nvim_buf_line_count(bufnr) + 1

  -- write content lines
  api.nvim_buf_set_lines(bufnr, line - 1, line - 1 + #lines, false, lines)

  -- trailing empty lines
  if opts.trailing_lines then
    for _ = 1, opts.trailing_lines, 1 do
      api.nvim_buf_set_lines(bufnr, -1, -1, false, {""})
    end
  end

  -- set extmarks
  if opts.mark then
    -- (empty line) start ext mark at 0
    -- start line
    -- ...
    -- end line
    -- (empty line)
    -- (empty line) end ext mark at 0
    -- except for title where we cant place initial mark on line -1

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

    return api.nvim_buf_set_extmark(
      bufnr,
      constants.OCTO_EM_NS,
      max(0, start_line - 1 - 1),
      0,
      {
        end_line = min(end_line + 2 - 1, api.nvim_buf_line_count(bufnr)),
        end_col = 0
      }
    )
  end
end

function M.write_title(bufnr, title, line)
  local title_mark = M.write_block({title, ""}, {bufnr = bufnr, mark = true, line = line})
  api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimIssueTitle", 0, 0, -1)
  api.nvim_buf_set_var(
    bufnr,
    "title",
    {
      saved_body = title,
      body = title,
      dirty = false,
      extmark = title_mark
    }
  )
end

function M.write_state(bufnr, state, number)
  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_TITLE_VT_NS, 0, -1)

  -- title virtual text
  local title_vt = {
    {tostring(number), "OctoNvimIssueId"},
    {format(" [%s] ", state), format("OctoNvimIssue%s", state)}
  }

  -- PR virtual text
  local status, pr = pcall(api.nvim_buf_get_var, bufnr, "pr")
  if status and pr then
    if pr.isDraft then
      table.insert(title_vt, {"[DRAFT] ", "OctoNvimIssueId"})
    end
  end
  api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_TITLE_VT_NS, 0, title_vt, {})
end

function M.write_body(bufnr, issue, line)
  local body = issue.body
  if vim.startswith(body, constants.NO_BODY_MSG) or util.is_blank(body) then
    body = " "
  end
  local description = string.gsub(body, "\r\n", "\n")
  local desc_mark = M.write_block(description, {bufnr = bufnr, mark = true, trailing_lines = 3, line = line})
  api.nvim_buf_set_var(
    bufnr,
    "description",
    {
      saved_body = description,
      body = description,
      dirty = false,
      extmark = desc_mark
    }
  )
end

function M.write_reactions(bufnr, reactions, line)
  -- clear namespace and set vt
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)

  local reaction_map = {
    ["THUMBS_UP"] = 0,
    ["THUMBS_DOWN"] = 0,
    ["LAUGH"] = 0,
    ["HOORAY"] = 0,
    ["CONFUSED"] = 0,
    ["HEART"] = 0,
    ["ROCKET"] = 0,
    ["EYES"] = 0,
    ["totalCount"] = reactions.totalCount
  }
  for _, reaction in ipairs(reactions.nodes) do
    reaction_map[reaction.content] = reaction_map[reaction.content] + 1
  end

  if reaction_map.totalCount > 0 then
    local reactions_vt = {}
    for reaction, count in pairs(reaction_map) do
      local content = util.reaction_map[reaction]
      if content and count > 0 then
        table.insert(reactions_vt, {"", "OctoNvimBubbleDelimiter"})
        table.insert(reactions_vt, {content, "OctoNvimBubbleBody"})
        table.insert(reactions_vt, {"", "OctoNvimBubbleDelimiter"})
        table.insert(reactions_vt, {format(" %s ", count), "Normal"})
      end
    end

    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, reactions_vt, {})
  end
  return line
end

function M.write_details(bufnr, issue, update)
  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DETAILS_VT_NS, 0, -1)

  local details = {}

  -- author
  local author_vt = {
    {"Created by: ", "OctoNvimDetailsLabel"},
    {issue.author.login, "OctoNvimDetailsValue"}
  }
  table.insert(details, author_vt)

  -- created_at
  local created_at_vt = {
    {"Created at: ", "OctoNvimDetailsLabel"},
    {util.format_date(issue.createdAt), "OctoNvimDetailsValue"}
  }
  table.insert(details, created_at_vt)

  if issue.state == "closed" then
    -- closed_at
    local closed_at_vt = {
      {"Closed at: ", "OctoNvimDetailsLabel"},
      {util.format_date(issue.closedAt), "OctoNvimDetailsValue"}
    }
    table.insert(details, closed_at_vt)
  else
    -- updated_at
    local updated_at_vt = {
      {"Updated at: ", "OctoNvimDetailsLabel"},
      {util.format_date(issue.updatedAt), "OctoNvimDetailsValue"}
    }
    table.insert(details, updated_at_vt)
  end

  -- assignees
  local assignees_vt = {
    {"Assignees: ", "OctoNvimDetailsLabel"}
  }
  if issue.assignees and #issue.assignees.nodes > 0 then
    for i, as in ipairs(issue.assignees.nodes) do
      table.insert(assignees_vt, {as.login, "OctoNvimDetailsValue"})
      if i ~= #issue.assignees.nodes then
        table.insert(assignees_vt, {", ", "OctoNvimDetailsLabel"})
      end
    end
  else
    table.insert(assignees_vt, {"No one assigned ", "OctoNvimMissingDetails"})
  end
  table.insert(details, assignees_vt)

  -- projects
  if issue.projectCards and #issue.projectCards.nodes > 0 then
    local projects_vt = {
      {"Projects: ", "OctoNvimDetailsLabel"}
    }
    local project_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("NormalFloat")), "bg#"):sub(2)
    local column_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("Comment")), "fg#"):sub(2)
    for _, card in ipairs(issue.projectCards.nodes) do
      table.insert(projects_vt, {card.column.name, })
      table.insert(projects_vt, {" (", "OctoNvimDetailsLabel"})
      table.insert(projects_vt, {card.project.name})
      table.insert(projects_vt, {")", "OctoNvimDetailsLabel"})
    end
    table.insert(details, projects_vt)
  end

  -- milestones
  local ms = issue.milestone
  local milestone_vt = {
    {"Milestone: ", "OctoNvimDetailsLabel"}
  }
  if ms ~= nil and ms ~= vim.NIL then
    table.insert(milestone_vt, {format("%s (%s)", ms.title, ms.state), "OctoNvimDetailsValue"})
  else
    table.insert(milestone_vt, {"No milestone", "OctoNvimMissingDetails"})
  end
  table.insert(details, milestone_vt)

  -- labels
  local labels_vt = {
    {"Labels: ", "OctoNvimDetailsLabel"}
  }
  if #issue.labels.nodes > 0 then
    for _, label in ipairs(issue.labels.nodes) do
      table.insert(labels_vt, {"", hl.create_highlight(label.color, {mode = "foreground"})})
      table.insert(labels_vt, {label.name, hl.create_highlight(label.color, {})})
      table.insert(labels_vt, {"", hl.create_highlight(label.color, {mode = "foreground"})})
      table.insert(labels_vt, {" ", "OctoNvimDetailsLabel"})
    end
  else
    table.insert(labels_vt, {"None yet", "OctoNvimMissingDetails"})
  end
  table.insert(details, labels_vt)

  -- for pull requests add additional details
  if issue.commits then
    -- Pending requested reviewers
    local requested_reviewers_vt = {
      {"Requested reviewers: ", "OctoNvimDetailsLabel"}
    }
    if issue.reviewRequests and issue.reviewRequests.totalCount > 0 then
      for i, reviewRequest in ipairs(issue.reviewRequests.nodes) do
        table.insert(
          requested_reviewers_vt,
          {reviewRequest.requestedReviewer.login or reviewRequest.requestedReviewer.name, "OctoNvimDetailsValue"}
        )
        if i ~= issue.reviewRequests.totalCount then
          table.insert(requested_reviewers_vt, {", ", "OctoNvimDetailsLabel"})
        end
      end
    else
      table.insert(requested_reviewers_vt, {"No reviewers", "OctoNvimMissingDetails"})
    end
    table.insert(details, requested_reviewers_vt)

    -- merged_by
    if issue.merged then
      local merged_by_vt = {
        {"Merged by: ", "OctoNvimDetailsLabel"},
        {issue.mergedBy.login, "OctoNvimDetailsValue"}
      }
      table.insert(details, merged_by_vt)
    end

    -- from/into branches
    local branches_vt = {
      {"From: ", "OctoNvimDetailsLabel"},
      {issue.headRefName, "OctoNvimDetailsValue"},
      {" Into: ", "OctoNvimDetailsLabel"},
      {issue.baseRefName, "OctoNvimDetailsValue"}
    }
    table.insert(details, branches_vt)

    -- review decision
    if issue.reviewDecision and issue.reviewDecision ~= vim.NIL then
      local decision_vt = {
        {"Review decision: ", "OctoNvimDetailsLabel"},
        {issue.reviewDecision, "OctoNvimDetailsValue"}
      }
      table.insert(details, decision_vt)
    end

    -- changes
    local unit = (issue.additions + issue.deletions) / 4
    local additions = math.floor(0.5 + issue.additions / unit)
    local deletions = math.floor(0.5 + issue.deletions / unit)
    local changes_vt = {
      {"Commits: ", "OctoNvimDetailsLabel"},
      {tostring(issue.commits.totalCount), "OctoNvimDetailsValue"},
      {" Changed files: ", "OctoNvimDetailsLabel"},
      {tostring(issue.changedFiles), "OctoNvimDetailsValue"},
      {" (", "OctoNvimDetailsLabel"},
      {format("+%d ", issue.additions), "DiffAdd"},
      {format("-%d ", issue.deletions), "DiffDelete"}
    }
    if additions > 0 then
      table.insert(changes_vt, {string.rep("■", additions), "DiffAdd"})
    end
    if deletions > 0 then
      table.insert(changes_vt, {string.rep("■", deletions), "DiffDelete"})
    end
    table.insert(changes_vt, {"■", "DiffChange"})
    table.insert(changes_vt, {")", "OctoNvimDetailsLabel"})
    table.insert(details, changes_vt)
  end

  local line = 3
  -- print #details + 2 empty lines
  local empty_lines = {}
  for _ = 1, #details + 2, 1 do
    table.insert(empty_lines, "")
  end
  if not update then
    M.write_block(empty_lines, {bufnr = bufnr, mark = false, line = line})
  end

  -- print details as virtual text
  for _, d in ipairs(details) do
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line - 1, d, {})
    line = line + 1
  end
end

function M.write_comment(bufnr, comment, line)
  -- heading
  line = line or api.nvim_buf_line_count(bufnr) + 1
  M.write_block({"", ""}, {bufnr = bufnr, mark = false, line = line})

  local header_vt = {
    {format("On %s ", util.format_date(comment.createdAt)), "OctoNvimCommentHeading"},
    {comment.author.login, "OctoNvimCommentUser"},
  }
  if comment.comments and comment.state then
    table.insert(header_vt, {" added a ", "OctoNvimCommentHeading"})
    table.insert(header_vt, {comment.state, "OctoNvimCommentValue"})
    table.insert(header_vt, {format(" review (%d comments)", comment.comments.totalCount), "OctoNvimCommentHeading"})
  else
    table.insert(header_vt, {" commented", "OctoNvimCommentHeading"})
  end

  local comment_vt_ns = api.nvim_buf_set_virtual_text(bufnr, 0, line - 1, header_vt, {})

  -- body
  line = line + 2
  local comment_body = string.gsub(comment.body, "\r\n", "\n")
  if vim.startswith(comment_body, constants.NO_BODY_MSG) or util.is_blank(comment_body) then
    comment_body = " "
  end
  local content = vim.split(comment_body, "\n", true)
  vim.list_extend(content, {"", "", ""})
  local comment_mark = M.write_block(content, {bufnr = bufnr, mark = true, line = line})

  -- reactions
  line = line + #content - 2
  local reaction_line = M.write_reactions(bufnr, comment.reactions, line)

  -- use v3 IDs
  if not tonumber(comment.id) then
    comment.id = util.graph2rest(comment.id)
  end

  -- update metadata
  local comments_metadata = api.nvim_buf_get_var(bufnr, "comments")
  table.insert(
    comments_metadata,
    {
      author = comment.author.name,
      id = comment.id,
      dirty = false,
      saved_body = comment_body,
      body = comment_body,
      extmark = comment_mark,
      namespace = comment_vt_ns,
      reaction_line = reaction_line,
      reactions = comment.reactions
    }
  )
  api.nvim_buf_set_var(bufnr, "comments", comments_metadata)
end

function M.write_diff_hunk(bufnr, diff_hunk, start_line)
  start_line = start_line or 1

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DIFFHUNKS_VT_NS, 0, start_line - 1)

  local lines = vim.split(diff_hunk, "\n")

  -- print #lines + 2 empty lines
  local empty_lines = {}
  local max_length = -1
  for _, l in ipairs(lines) do
    table.insert(empty_lines, "")
    if #l > max_length then
      max_length = #l
    end
  end
  max_length = math.max(max_length, vim.fn.winwidth(0) - 8)
  vim.list_extend(empty_lines, {"", "", ""})
  M.write_block(empty_lines, {bufnr = bufnr, mark = false, line = start_line})

  local vt_lines = {}
  table.insert(vt_lines, {{format("┌%s┐", string.rep("─", max_length + 2))}})
  for _, line in ipairs(lines) do
    if vim.startswith(line, "@@ ") then
      local index = string.find(line, "@[^@]*$")
      table.insert(
        vt_lines,
        {
          {"│ "},
          {string.sub(line, 0, index), "DiffLine"},
          {string.sub(line, index + 1), "DiffSubname"},
          {string.rep(" ", 1 + max_length - #line)},
          {"│"}
        }
      )
    elseif vim.startswith(line, "+") then
      table.insert(
        vt_lines,
        {
          {"│ "},
          {line, "DiffAdd"},
          {string.rep(" ", max_length - #line)},
          {" │"}
        }
      )
    elseif vim.startswith(line, "-") then
      table.insert(
        vt_lines,
        {
          {"│ "},
          {line, "DiffDelete"},
          {string.rep(" ", max_length - #line)},
          {" │"}
        }
      )
    else
      table.insert(
        vt_lines,
        {
          {"│ "},
          {line},
          {string.rep(" ", max_length - #line)},
          {" │"}
        }
      )
    end
  end
  table.insert(vt_lines, {{format("└%s┘", string.rep("─", max_length + 2))}})

  -- print diff_hunk as virtual text
  local line = start_line - 1
  for _, vt_line in ipairs(vt_lines) do
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line, vt_line, {})
    line = line + 1
  end
end

function M.write_diff_hunk2(bufnr, diff_hunk, start_line, position)
  start_line = start_line or 1

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DIFFHUNKS_VT_NS, 0, start_line - 1)

  local lines = vim.split(diff_hunk, "\n")

  local linenr_length = #tostring(position) + 1
  local display_lines = {}
  local empty_lines = {}
  local max_length = -1
  for i=math.max(2, #lines - 3), #lines do
    table.insert(empty_lines, "")
    if #lines[i] > max_length then
      max_length = #lines[i]
    end
    table.insert(display_lines, lines[i])
  end
  -- TODO: support multi line comments
  max_length = math.max(max_length + 1, vim.fn.winwidth(0) - 8)
  vim.list_extend(empty_lines, {"", "", ""})
  M.write_block(empty_lines, {bufnr = bufnr, mark = false, line = start_line})

  local vt_lines = {}
  table.insert(vt_lines, {{string.rep(" ", linenr_length) .. format("┌%s┐", string.rep("─", max_length + 2))}})
  for i, line in ipairs(display_lines) do
    local hlpos, hlbar = nil
    -- if i > position - 3 then
      --hlpos = "OctoNvimDiffHunkPosition"
      -- hlbar = "OctoNvimBubbleRed"
    -- end
    -- if vim.startswith(line, "@@ ") then
    --   local index = string.find(line, "@[^@]*$")
    --   table.insert(
    --     vt_lines,
    --     {
    --       {"│ ", hlbar or "Normal"},
    --       {string.sub(line, 0, index), hlpos or "DiffLine"},
    --       {string.sub(line, index + 1), hlpos or "DiffSubname"},
    --       {string.rep(" ", max_length - #line), hlpos or "Normal"},
    --       {" │", hlbar or "Normal"},
    --     }
    --   )
    -- else
    if vim.startswith(line, "+") then
      table.insert(
        vt_lines,
        {
          {tostring(position - #display_lines + i) .. " ", "Comment"},
          {"│ ", hlbar or "Normal"},
          {line, hlpos or "DiffAdd"},
          {string.rep(" ", max_length - #line), hlpos or "Normal"},
          {" │", hlbar or "Normal"},
        }
      )
    elseif vim.startswith(line, "-") then
      table.insert(
        vt_lines,
        {
          {tostring(position - #display_lines + i) .. " ", "Comment"},
          {"│ ", hlbar or "Normal"},
          {line, hlpos or "DiffDelete"},
          {string.rep(" ", max_length - #line), hlpos or "Normal"},
          {" │", hlbar or "Normal"},
        }
      )
    else
      table.insert(
        vt_lines,
        {
          {tostring(position - #display_lines + i) .. " ", "Comment"},
          {"│ ", hlbar or "Normal"},
          {line, hlpos or "DiffDelete"},
          {line, hlpos or "Normal"},
          {string.rep(" ", max_length - #line), hlpos or "Normal"},
          {" │", hlbar or "Normal"},
        }
      )
    end
  end
  table.insert(vt_lines, {{string.rep(" ", linenr_length) .. format("└%s┘", string.rep("─", max_length + 2))}})

  -- print diff_hunk as virtual text
  local line = start_line - 1
  for _, vt_line in ipairs(vt_lines) do
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line, vt_line, {})
    line = line + 1
  end
end

return M
