local constants = require "octo.constants"
local util = require "octo.util"
local bubbles = require "octo.ui.bubbles"
local vim = vim
local api = vim.api
local max = math.max
local min = math.min
local format = string.format

local M = {}

function M.write_block(bufnr, lines, line, mark)
  bufnr = bufnr or api.nvim_get_current_buf()
  line = line or api.nvim_buf_line_count(bufnr) + 1
  mark = mark or false

  if type(lines) == "string" then
    lines = vim.split(lines, "\n", true)
  end

  -- write content lines
  api.nvim_buf_set_lines(bufnr, line - 1, line - 1 + #lines, false, lines)

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

    return api.nvim_buf_set_extmark(
      bufnr,
      constants.OCTO_COMMENT_NS,
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
  local title_mark = M.write_block(bufnr, {title, ""}, line, true)
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
  bufnr = bufnr or api.nvim_get_current_buf()
  state = state or api.nvim_buf_get_var(bufnr, "state")
  number = number or api.nvim_buf_get_var(bufnr, "number")

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_TITLE_VT_NS, 0, -1)

  -- title virtual text
  local title_vt = {
    {tostring(number), "OctoNvimIssueId"},
    {format(" [%s] ", state), util.state_hl_map[state]}
  }

  -- PR virtual text
  local status, pr = pcall(api.nvim_buf_get_var, bufnr, "pr")
  if status and pr then
    if pr.isDraft then
      table.insert(title_vt, {"[DRAFT] ", "OctoNvimIssueId"})
    end
  end
  M.write_virtual_text(bufnr, constants.OCTO_TITLE_VT_NS, 0, title_vt)
end

function M.write_body(bufnr, issue, line)
  local body = vim.fn.trim(issue.body)
  if vim.startswith(body, constants.NO_BODY_MSG) or util.is_blank(body) then
    body = " "
  end
  local description = body:gsub("\r\n", "\n")
  local lines = vim.split(description, "\n", true)
  vim.list_extend(lines, {""})
  local desc_mark = M.write_block(bufnr, lines, line, true)
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

function M.write_reactions(bufnr, reaction_groups, line, mode)

  mode = mode or "append"

  -- clear namespace and set vt
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)

  local reactions_count = 0
  local reactions_vt = {}
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count  + 1
      local icon = util.reaction_map[group.content]
      local bubble = bubbles.make_reaction_bubble(icon, group.viewerHasReacted)
      local count = format(" %s ", group.users.totalCount)
      vim.list_extend(reactions_vt, bubble)
      table.insert(reactions_vt, { count, "Normal" })
    end
  end
  if mode == "delete" and reactions_count == 0 and line then
    api.nvim_buf_set_lines(bufnr, line, line+2, false, {})
    api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)
    return nil
  elseif reactions_count > 0 then
    if mode == "append" then
      M.write_block(bufnr, {"", ""}, line)
      M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, reactions_vt)
    elseif mode == "insert" then
      api.nvim_buf_set_lines(bufnr, line, line, false, {"", ""})
      M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line, reactions_vt)
    else
      M.write_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, reactions_vt)
    end
    return line
  else
    return nil
  end

end

function M.write_details(bufnr, issue, update)
  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DETAILS_VT_NS, 0, -1)

  local details = {}

  -- author
  local author_vt = {{"Created by: ", "OctoNvimDetailsLabel"}}
  local author_bubble = bubbles.make_user_bubble(
    issue.author.login,
    issue.viewerDidAuthor
  )

  vim.list_extend(author_vt, author_bubble)
  table.insert(details, author_vt)

  -- created_at
  local created_at_vt = {
    {"Created at: ", "OctoNvimDetailsLabel"},
    {util.format_date(issue.createdAt), "OctoNvimDetailsValue"}
  }
  table.insert(details, created_at_vt)

  if issue.state == "CLOSED" then
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
    for _, assignee in ipairs(issue.assignees.nodes) do
      local user_bubble = bubbles.make_user_bubble(assignee.login, assignee.isViewer, { margin_width = 1 })
      vim.list_extend(assignees_vt, user_bubble)
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
    --local project_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("NormalFloat")), "bg#"):sub(2)
    --local column_color = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("Comment")), "fg#"):sub(2)
    for _, card in ipairs(issue.projectCards.nodes) do
      if card.column ~= vim.NIL then
        table.insert(projects_vt, {card.column.name, })
        table.insert(projects_vt, {" (", "OctoNvimDetailsLabel"})
        table.insert(projects_vt, {card.project.name})
        table.insert(projects_vt, {")", "OctoNvimDetailsLabel"})
      end
    end
    table.insert(details, projects_vt)
  end

  -- milestones
  local ms = issue.milestone
  local milestone_vt = {
    {"Milestone: ", "OctoNvimDetailsLabel"}
  }
  if ms ~= nil and ms ~= vim.NIL then
    table.insert(milestone_vt, {ms.title, "OctoNvimDetailsValue"})
    table.insert(milestone_vt, {format(" (%s)", util.state_hl_map[ms.state]), "OctoNvimDetailsValue"})
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
      local label_bubble = bubbles.make_label_bubble(
        label.name,
        label.color,
        { margin_width = 1 }
      )
      vim.list_extend(labels_vt, label_bubble)
    end
  else
    table.insert(labels_vt, {"None yet", "OctoNvimMissingDetails"})
  end
  table.insert(details, labels_vt)

  -- additional details for pull requests
  if issue.commits then
    -- reviewers
    local reviewers = {}
    local collect_reviewer = function (name, state)
      --if vim.g.octo_viewer ~= name then
        if not reviewers[name] then
          reviewers[name] = {state}
        else
          local states = reviewers[name]
          if not vim.tbl_contains(states, state) then
            table.insert(states, state)
          end
          reviewers[name] = states
        end
      --end
    end
    for _, item in ipairs(issue.timelineItems.nodes) do
      if item.__typename == "PullRequestReview" then
        local name = item.author.login
        collect_reviewer(name, item.state)
      end
    end
    if issue.reviewRequests and issue.reviewRequests.totalCount > 0 then
      for _, reviewRequest in ipairs(issue.reviewRequests.nodes) do
        local name = reviewRequest.requestedReviewer.login or reviewRequest.requestedReviewer.name
        collect_reviewer(name, "REVIEW_REQUIRED")
      end
    end
    local reviewers_vt = {
      {"Reviewers: ", "OctoNvimDetailsLabel"}
    }
    if #vim.tbl_keys(reviewers) > 0 then
      for _, name in ipairs(vim.tbl_keys(reviewers)) do
        local strongest_review = util.calculate_strongest_review_state(reviewers[name])
        local reviewer_vt = {
          {name , "OctoNvimUser"},
          {" "},
          {util.state_icon_map[strongest_review], util.state_hl_map[strongest_review]},
          {" "},
        }
        vim.list_extend(reviewers_vt, reviewer_vt)
      end
    else
      table.insert(reviewers_vt, {"No reviewers", "OctoNvimMissingDetails"})
    end
    table.insert(details, reviewers_vt)

    -- merged_by
    if issue.merged then
      local merged_by_vt = {{"Merged by: ", "OctoNvimDetailsLabel"}}
      local name = issue.mergedBy.login or issue.mergedBy.name
      local is_viewer = issue.mergedBy.isViewer or false
      local user_bubble = bubbles.make_user_bubble(name, is_viewer)
      vim.list_extend(merged_by_vt, user_bubble)
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
        {util.state_message_map[issue.reviewDecision]},
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
      {format("+%d ", issue.additions), "OctoNvimPullAdditions"},
      {format("-%d ", issue.deletions), "OctoNvimPullDeletions"}
    }
    if additions > 0 then
      table.insert(changes_vt, {string.rep("■", additions), "OctoNvimPullAdditions"})
    end
    if deletions > 0 then
      table.insert(changes_vt, {string.rep("■", deletions), "OctoNvimPullDeletions"})
    end
    table.insert(changes_vt, {"■", "OctiNvimPullModifications"})
    table.insert(changes_vt, {")", "OctoNvimDetailsLabel"})
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

  -- heading
  line = line or api.nvim_buf_line_count(bufnr) + 1
  local start_line = line
  M.write_block(bufnr, {"", ""}, line)

  local header_vt = {}
  local author_bubble = bubbles.make_user_bubble(
    comment.author.login,
    comment.viewerDidAuthor,
    { margin_width = 1 }
  )

  if kind == "PullRequestReview" then
    -- Review top-level comments
    table.insert(header_vt, {"REVIEW:", "OctoNvimTimelineItemHeading"})
    vim.list_extend(header_vt, author_bubble)
    table.insert(header_vt, {comment.state:lower().." ", util.state_hl_map[comment.state]})
    table.insert(header_vt, {"(", "OctoNvimSymbol"})
    table.insert(header_vt, {util.format_date(comment.createdAt), "OctoNvimDate"})
    table.insert(header_vt, {")", "OctoNvimSymbol"})
  elseif kind == "PullRequestReviewComment" then
    -- Review thread comments
    table.insert(header_vt, {"THREAD COMMENT: ", "OctoNvimTimelineItemHeading"})
    vim.list_extend(header_vt, author_bubble)
    table.insert(header_vt, {comment.state:lower().." ", util.state_hl_map[comment.state]})
    table.insert(header_vt, {"(", "OctoNvimSymbol"})
    table.insert(header_vt, {util.format_date(comment.createdAt), "OctoNvimDate"})
    table.insert(header_vt, {")", "OctoNvimSymbol"})
  elseif kind == "IssueComment" then
    -- Issue comments
    table.insert(header_vt, {"COMMENT: ", "OctoNvimTimelineItemHeading"})
    vim.list_extend(header_vt, author_bubble)
    table.insert(header_vt, {"(", "OctoNvimSymbol"})
    table.insert(header_vt, {util.format_date(comment.createdAt), "OctoNvimDate"})
    table.insert(header_vt, {")", "OctoNvimSymbol"})
  end
  local comment_vt_ns = api.nvim_create_namespace("")
  M.write_virtual_text(bufnr, comment_vt_ns, line - 1, header_vt)

  if kind == "PullRequestReview" and util.is_blank(comment.body) then
    -- do not render empty review comments
    return start_line, start_line+1
  end

  -- body
  line = line + 2
  local comment_body = vim.fn.trim(string.gsub(comment.body, "\r\n", "\n"))
  if vim.startswith(comment_body, constants.NO_BODY_MSG) or util.is_blank(comment_body) then
    comment_body = " "
  end
  local content = vim.split(comment_body, "\n", true)
  vim.list_extend(content, {""})
  local comment_mark = M.write_block(bufnr, content, line, true)

  -- reactions
  line = line + #content
  local reaction_line = M.write_reactions(bufnr, comment.reactionGroups, line)
  if reaction_line then line = line + 2 end

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
      reaction_groups = comment.reactionGroups,
      kind = kind,
      first_comment_id = comment.first_comment_id,
    }
  )
  api.nvim_buf_set_var(bufnr, "comments", comments_metadata)

  return start_line, line - 1
end

local function find_snippet_range(diffhunk_lines)
  local context_lines = vim.g.octo_snippet_context_lines or 4
  local snippet_start
  local count = 0
  for i = #diffhunk_lines, 1, -1 do
    local line = diffhunk_lines[i]

    -- once we find a where the snippet should start, add `context_lines` of context
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

    -- if we cant find a lower bondary in last `context_lines` then set boundary
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
      {string.rep(" ", opts.max_lnum), "DiffAdd"},
      {" ", "DiffAdd"},
      {string.rep(" ", opts.max_lnum - #tostring(opts.right_line))..tostring(opts.right_line), "DiffAdd"},
      {" ", "DiffAdd"}
    }
  elseif not opts.right_line and opts.left_line then
    return {
      {string.rep(" ", opts.max_lnum - #tostring(opts.left_line))..tostring(opts.left_line), "DiffDelete"},
      {" ", "DiffDelete"},
      {string.rep(" ", opts.max_lnum), "DiffDelete"},
      {" ", "DiffDelete"}
    }
  elseif opts.right_line and opts.left_line then
    return {
      {string.rep(" ", opts.max_lnum - #tostring(opts.left_line))..tostring(opts.left_line)},
      {" "},
      {string.rep(" ", opts.max_lnum - #tostring(opts.right_line))..tostring(opts.right_line)},
      {" "}
    }
  end
end

function M.write_diff_hunk(bufnr, diffhunk, start_line, comment_start, comment_end, comment_side)
  start_line = start_line or api.nvim_buf_line_count(bufnr) + 1

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DIFFHUNKS_VT_NS, 0, start_line - 1)

  local diffhunk_lines = vim.split(diffhunk, "\n")

  -- generate maps from diffhunk line to code line:
  --- right_side_lines
  --- left_side_lines
  local diff_directive = diffhunk_lines[1]
  local left_offset, right_offset  = string.match(diff_directive, "@@%s%-(%d+),%d+%s%+(%d+),%d+%s@@")
  local right_side_lines = {}
  local left_side_lines = {}
  local right_side_line = right_offset
  local left_side_line = left_offset
  for i=2, #diffhunk_lines do
    local line = diffhunk_lines[i]
    if vim.startswith(line, "+") then
      right_side_lines[i] = right_side_line
      right_side_line = right_side_line + 1
    elseif vim.startswith(line, "-") then
      left_side_lines[i] = left_side_line
      left_side_line = left_side_line + 1
    elseif not vim.startswith(line, "-") and not vim.startswith(line, "+") then
      right_side_lines[i] = right_side_line
      left_side_lines[i] = left_side_line
      right_side_line = right_side_line + 1
      left_side_line = left_side_line + 1
    end
  end

  -- calculate length of the higher line number
  local max_lnum = math.max(#tostring(right_offset + #diffhunk_lines), #tostring(left_offset + #diffhunk_lines))

  -- calculate diffhunk subrange to show
  local snippet_start, snippet_end
  if comment_side and comment_start ~= comment_end then
    -- for multiline comments, discard calculated values
    -- write just those lines
    local side_lines
    if comment_side == "RIGHT" then
      side_lines = right_side_lines
    elseif comment_side == "LEFT" then
      side_lines = left_side_lines
    end
    for pos, l in pairs(side_lines) do
      if l == comment_start then
        snippet_start = pos
      elseif l == comment_end then
        snippet_end = pos
      end
    end
  else
    -- for single-line comment, add additional context lines
    snippet_start, snippet_end = find_snippet_range(diffhunk_lines)
  end

  -- calculate longest line in the visible section of the diffhunk
  local max_length = -1
  for i = snippet_start, snippet_end do
    local line = diffhunk_lines[i]
    if #line > max_length then
      max_length = #line
    end
  end
  max_length = math.max(max_length, vim.fn.winwidth(0) - 10 - vim.wo.foldcolumn)

  -- write empty lines to hold virtual text
  local empty_lines = {}
  for _ = snippet_start, snippet_end + 3 do
    table.insert(empty_lines, "")
  end
  M.write_block(bufnr, empty_lines, start_line)

  -- prepare vt chunks
  local vt_lines = {}
  table.insert(vt_lines, {{format("┌%s┐", string.rep("─", max_length + 2))}})
  for i = snippet_start, snippet_end do
    local line = diffhunk_lines[i]

    if vim.startswith(line, "@@ ") then
      local index = string.find(line, "@[^@]*$")
      table.insert(
        vt_lines,
        {
          {"│"},
          {string.rep(" ", 2*max_lnum +1), "DiffLine"},
          {string.sub(line, 0, index), "DiffLine"},
          {string.sub(line, index + 1), "DiffLine"},
          {string.rep(" ", 1 + max_length - #line - 2*max_lnum), "DiffLine"},
          {"│"}
        }
      )
    elseif vim.startswith(line, "+") then
      local vt_line = {{"│"}}
      vim.list_extend(vt_line, get_lnum_chunks({right_line=right_side_lines[i], max_lnum=max_lnum}))
      vim.list_extend(vt_line, {
        {line:gsub("^.", " "), "DiffAdd"},
        {string.rep(" ", max_length - #line - 2*max_lnum), "DiffAdd"},
        {"│"}
      })
      table.insert(vt_lines, vt_line)
    elseif vim.startswith(line, "-") then
      local vt_line = {{"│"}}
      vim.list_extend(vt_line, get_lnum_chunks({left_line=left_side_lines[i], max_lnum=max_lnum}))
      vim.list_extend(vt_line, {
        {line:gsub("^.", " "), "DiffDelete"},
        {string.rep(" ", max_length - #line - 2*max_lnum), "DiffDelete"},
        {"│"}
      })
      table.insert(vt_lines, vt_line)
    else
      local vt_line = {{"│"}}
      vim.list_extend(vt_line, get_lnum_chunks({left_line=left_side_lines[i], right_line=right_side_lines[i], max_lnum=max_lnum}))
      vim.list_extend(vt_line, {
        {line},
        {string.rep(" ", max_length - #line - 2*max_lnum)},
        {"│"}
      })
      table.insert(vt_lines, vt_line)
    end
  end
  table.insert(vt_lines, {{format("└%s┘", string.rep("─", max_length + 2))}})

  -- write snippet as virtual text
  local line = start_line - 1
  for _, vt_line in ipairs(vt_lines) do
    M.write_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line, vt_line)
    line = line + 1
  end

  return start_line, line
end

function M.write_thread_snippet(bufnr, diffhunk, side, start_pos, end_pos, start_line)
  start_line = start_line or api.nvim_buf_line_count(bufnr) + 1
  start_pos = start_pos ~= vim.NIL and start_pos or end_pos

  -- add context for single-line comments
  if start_pos == end_pos then
    local context_lines = vim.g.octo_snippet_context_lines or 3
    start_pos = start_pos - context_lines
  end

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DIFFHUNKS_VT_NS, 0, start_line - 1)

  local diffhunk_lines = vim.split(diffhunk, "\n")

  -- write end_pos - start_pos + 2 borders + 2 empty lines
  -- to hold virtual text
  local empty_lines = {}
  for _=1,(end_pos-start_pos+4) do
    table.insert(empty_lines, "")
  end
  M.write_block(bufnr, empty_lines, start_line)

  -- separate diffhunk lines into right/left hunks
  local diff_directive = diffhunk_lines[1]
  local side_lines = {}
  for i=2,#diffhunk_lines do
    local line = diffhunk_lines[i]
    if vim.startswith(line, "+") and side == "RIGHT" then
      table.insert(side_lines, line)
    elseif vim.startswith(line, "-") and side == "LEFT" then
      table.insert(side_lines, line)
    elseif not vim.startswith(line, "-") and not vim.startswith(line, "+") then
      table.insert(side_lines, line)
    end
  end

  -- calculate longest hunk line
  local max_length = -1
  for _, line in ipairs(side_lines) do
    max_length = math.max(max_length, #line)
  end
  max_length = math.min(max_length, vim.fn.winwidth(0) - 10 - vim.wo.foldcolumn) + 1

  local left_offset, right_offset  = string.match(diff_directive, "@@%s%-(%d+),%d+%s%+(%d+),%d+%s@@")
  local offset = side == "RIGHT" and right_offset or left_offset
  local final_lines = {unpack(side_lines, start_pos - offset + 1, end_pos - offset + 1)}
  local vt_lines = {}
  local max_lnum = math.max(#tostring(start_pos), #tostring(end_pos))
  table.insert(vt_lines, {{format("┌%s┐", string.rep("─", max_lnum + max_length + 2))}})
  for i, line in ipairs(final_lines) do
    local stripped_line = line:gsub("^.", " ")
    local hl_line = side == "RIGHT" and "DiffAdd" or "DiffDelete"
    local vt_line = {stripped_line, hl_line}
    local lnum = tostring(i + start_pos - 1)
    local lnum_length = #lnum
    local padded_lnum = string.rep("0", max_lnum - lnum_length)..lnum
    table.insert( vt_lines, {
      {"│"},
      {format(" %s ", padded_lnum), "DiffChange"},
      vt_line,
      {string.rep(" ", max_length - #stripped_line), hl_line},
      {"│"}
    })
  end
  table.insert(vt_lines, {{format("└%s┘", string.rep("─", max_lnum + max_length + 2))}})

  -- write diffhunk as virtual text
  local line = start_line - 1
  for _, vt_line in ipairs(vt_lines) do
    M.write_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line, vt_line)
    line = line + 1
  end

  return start_line, line
end

function M.write_review_thread_header(bufnr, opts, line)
  line = line or api.nvim_buf_line_count(bufnr) - 1

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_THREAD_HEADER_VT_NS, line, line + 2)

  local header_vt = {
    {"THREAD: ", "OctoNvimTimelineItemHeading"},
    {"[", "OctoNvimSymbol"},
    {opts.path.." ", "OctoNvimDetailsLabel"},
    {tostring(opts.start_line)..":"..tostring(opts.end_line), "OctoNvimDetailsValue"},
    {"] ", "OctoNvimSymbol"},
  }
  if opts.isOutdated then
    local outdated_bubble = bubbles.make_bubble(
      "outdated",
      "OctoNvimBubbleRed",
      { margin_width = 1 }
    )
    vim.list_extend(header_vt, outdated_bubble)
  end

  if opts.isResolved then
    local resolved_bubble = bubbles.make_bubble(
      "resolved",
      "OctoNvimBubbleGreen",
      { margin_width = 1 }
    )
    vim.list_extend(header_vt, resolved_bubble)
  end

  M.write_block(bufnr, {""})
  M.write_virtual_text(bufnr, constants.OCTO_THREAD_HEADER_VT_NS, line + 1, header_vt)
end

function M.write_issue_summary(bufnr, issue, opts)
  opts = opts or {}
  local max_length = opts.max_length or 80
  local chunks = {}

  -- repo and date line
  table.insert(chunks, {
    {issue.repository.nameWithOwner, "OctoNvimDetailsValue"},
    {" on ", "OctoNvimDetailsLabel"},
    {util.format_date(issue.createdAt), "OctoNvimDetailsValue"}
  })

  -- issue body
  table.insert(chunks, {
    {"["..issue.state.."] ", util.state_hl_map[issue.state]},
    {issue.title.." ", "OctoNvimDetailsLabel"},
    {"#"..issue.number.." ", "OctoNvimDetailsValue"}
  })
  table.insert(chunks, {{""}})

  -- issue body
  local body = vim.split(issue.body, "\n")
  body = table.concat(body, " ")
  body = body:gsub('[%c]', ' ')
  body = body:sub(1, max_length - 4 - 2).."…"
  table.insert(chunks, {
    {body}
  })
  table.insert(chunks, {{""}})

  -- labels
  if #issue.labels.nodes > 0 then
    local labels = {}
    for _, label in ipairs(issue.labels.nodes) do
      local label_bubble = bubbles.make_label_bubble(
        label.name,
        label.color,
        { margin_width = 1 }
      )
      vim.list_extend(labels, label_bubble)
    end
    table.insert(chunks, labels)
    table.insert(chunks, {{""}})
  end

  -- PR branches
  if issue.__typename == "PullRequest" then
    table.insert(chunks, {
      {"[", "OctoNvimDetailsValue"},
      {issue.baseRefName, "OctoNvimDetailsLabel"},
      {"] ⟵ [", "OctoNvimDetailsValue"},
      {issue.headRefName, "OctoNvimDetailsLabel"},
      {"]", "OctoNvimDetailsValue"},
    })
    table.insert(chunks, {{""}})
  end

  -- author line
  table.insert(chunks, {
    {vim.g.octo_icon_user or " "},
    {issue.author.login}
  })

  for i=1,#chunks do
    M.write_block(bufnr, {""}, i)
  end
  for i=1,#chunks do
    M.write_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, i-1, chunks[i])
  end
  return #chunks
end

local function write_event(bufnr, vt)
  local line = api.nvim_buf_line_count(bufnr) - 1
  M.write_block(bufnr, {""}, line + 2)
  M.write_virtual_text(bufnr, constants.OCTO_EVENT_VT_NS, line+1, vt)
end

function M.write_assigned_event(bufnr, item)
  local actor_bubble = bubbles.make_user_bubble(
    item.actor.login,
    item.actor.login == vim.g.octo_viewer
  )
  local vt = {}
  table.insert(vt, {"EVENT: ", "OctoNvimTimelineItemHeading"})
  vim.list_extend(vt, actor_bubble)
  table.insert(vt, {" assigned this to ", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {item.assignee.login or item.assignee.name, "OctoNvimDetailsLabel"})
  table.insert(vt, {" (", "OctoNvimSymbol"})
  table.insert(vt, {util.format_date(item.createdAt), "OctoNvimDate"})
  table.insert(vt, {")", "OctoNvimSymbol"})
  write_event(bufnr, vt)
end

function M.write_commit_event(bufnr, item)
  local commiter_bubble = bubbles.make_user_bubble(
    item.commit.committer.user.login,
    item.commit.committer.user.login == vim.g.octo_viewer
  )
  local vt = {}
  table.insert(vt, {"EVENT: ", "OctoNvimTimelineItemHeading"})
  vim.list_extend(vt, commiter_bubble)
  table.insert(vt, {" added ", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {item.commit.abbreviatedOid, "OctoNvimDetailsLabel"})
  table.insert(vt, {" '", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {item.commit.messageHeadline, "OctoNvimDetailsLabel"})
  table.insert(vt, {"' (", "OctoNvimSymbol"})
  table.insert(vt, {util.format_date(item.createdAt), "OctoNvimDate"})
  table.insert(vt, {")", "OctoNvimSymbol"})
  write_event(bufnr, vt)
end

function M.write_merged_event(bufnr, item)
  local actor_bubble = bubbles.make_user_bubble(
    item.actor.login,
    item.actor.login == vim.g.octo_viewer
  )
  local vt = {}
  table.insert(vt, {"EVENT: ", "OctoNvimTimelineItemHeading"})
  vim.list_extend(vt, actor_bubble)
  table.insert(vt, {" merged commit ", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {item.commit.abbreviatedOid, "OctoNvimDetailsLabel"})
  table.insert(vt, {" into ", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {item.mergeRefName, "OctoNvimTimelineItemHeading"})
  table.insert(vt, {" (", "OctoNvimSymbol"})
  table.insert(vt, {util.format_date(item.createdAt), "OctoNvimDate"})
  table.insert(vt, {")", "OctoNvimSymbol"})
  write_event(bufnr, vt)
end

function M.write_closed_event(bufnr, item)
  local actor_bubble = bubbles.make_user_bubble(
    item.actor.login,
    item.actor.login == vim.g.octo_viewer
  )
  local vt = {}
  table.insert(vt, {"EVENT: ", "OctoNvimTimelineItemHeading"})
  vim.list_extend(vt, actor_bubble)
  table.insert(vt, {" closed this ", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {"(", "OctoNvimSymbol"})
  table.insert(vt, {util.format_date(item.createdAt), "OctoNvimDate"})
  table.insert(vt, {")", "OctoNvimSymbol"})
  write_event(bufnr, vt)
end

function M.write_reopened_event(bufnr, item)
  local actor_bubble = bubbles.make_user_bubble(
    item.actor.login,
    item.actor.login == vim.g.octo_viewer
  )
  local vt = {}
  table.insert(vt, {"EVENT: ", "OctoNvimTimelineItemHeading"})
  vim.list_extend(vt, actor_bubble)
  table.insert(vt, {" reopened this ", "OctoNvimTimelineItemHeading"})
  table.insert(vt, {"(", "OctoNvimSymbol"})
  table.insert(vt, {util.format_date(item.createdAt), "OctoNvimDate"})
  table.insert(vt, {")", "OctoNvimSymbol"})
  write_event(bufnr, vt)
end

function M.write_virtual_text(bufnr, ns, line, chunks)
  --api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text=chunks, virt_text_pos='overlay'})
  api.nvim_buf_set_virtual_text(bufnr, ns, line, chunks, {})
end

return M
