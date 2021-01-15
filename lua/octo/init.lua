local gh = require "octo.gh"
local signs = require "octo.signs"
local hl = require "octo.highlights"
local constants = require "octo.constants"
local util = require "octo.util"
local graphql = require "octo.graphql"
local vim = vim
local api = vim.api
local max = math.max
local min = math.min
local format = string.format
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

function M.check_login()
  gh.run(
    {
      args = {"auth", "status"},
      cb = function(_, err)
        local _, _, name = string.find(err, "Logged in to [^%s]+ as ([^%s]+)")
        vim.g.octo_loggedin_user = name
      end
    }
  )
end

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
  if issue.assignees and #issue.assignees > 0 then
    for i, as in ipairs(issue.assignees) do
      table.insert(assignees_vt, {as.login, "OctoNvimDetailsValue"})
      if i ~= #issue.assignees then
        table.insert(assignees_vt, {", ", "OctoNvimDetailsLabel"})
      end
    end
  else
    table.insert(assignees_vt, {"No one assigned ", "OctoNvimMissingDetails"})
  end
  table.insert(details, assignees_vt)

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

  -- for pulls add additional details
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
    {" commented", "OctoNvimCommentHeading"}
  }
  local comment_vt_ns = api.nvim_buf_set_virtual_text(bufnr, 0, line - 1, header_vt, {})

  -- TODO: if present, print `outdated` and `state`

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

function M.write_diff_hunk(bufnr, diff_hunk, start_line, position)
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

function M.load_issue()
  local bufname = vim.fn.bufname()
  local repo, type, number = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if not repo or not type or not number then
    api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end

  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  local query, key
  if type == "pull" then
    query = format(graphql.pull_request_query, owner, name, number)
    key = "pullRequest"
  elseif type == "issue" then
    query = format(graphql.issue_query, owner, name, number)
    key = "issue"
  end
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = util.aggregate_pages(output, format("data.repository.%s.comments.nodes", key))
          M.create_buffer(type, resp.data.repository[key], repo, false)
        end
      end
    }
  )
end

-- This function accumulates all the taggable users into a single list that
-- gets set as a buffer variable `taggable_users`. If this list of users
-- is needed syncronously, this function will need to be refactored.
-- The list of taggable users should contain:
--   - The PR author
--   - The authors of all the existing comments
--   - The contributors of the repo
local function async_fetch_taggable_users(bufnr, repo, participants)
  local users = api.nvim_buf_get_var(bufnr, "taggable_users") or {}

  -- add participants
  for _, p in pairs(participants) do
    table.insert(users, p.login)
  end

  -- add comment authors
  local comments_metadata = api.nvim_buf_get_var(bufnr, "comments")
  for _, c in pairs(comments_metadata) do
    table.insert(users, c.author)
  end

  -- add repo contributors
  api.nvim_buf_set_var(bufnr, "taggable_users", users)
  gh.run(
    {
      args = {"api", format("repos/%s/contributors", repo)},
      cb = function(response)
        local resp = json.parse(response)
        for _, contributor in ipairs(resp) do
          table.insert(users, contributor.login)
        end
        api.nvim_buf_set_var(bufnr, "taggable_users", users)
      end
    }
  )
end

-- This function fetches the issues in the repo so they can be used for
-- completion.
local function async_fetch_issues(bufnr, repo)
  gh.run(
    {
      args = {"api", format(format("repos/%s/issues", repo))},
      cb = function(response)
        local issues_metadata = {}
        local resp = json.parse(response)
        for _, issue in ipairs(resp) do
          table.insert(issues_metadata, {number = issue.number, title = issue.title})
        end
        api.nvim_buf_set_var(bufnr, "issues", issues_metadata)
      end
    }
  )
end

function M.create_buffer(type, obj, repo, create)
  if not obj.id then
    api.nvim_err_writeln(format("Cannot find issue in %s", repo))
    return
  end

  local iid = obj.id
  local number = obj.number
  local state = obj.state

  local bufnr
  if create then
    bufnr = api.nvim_create_buf(true, false)
    api.nvim_set_current_buf(bufnr)
    vim.cmd(format("file octo://%s/%s/%d", repo, type, number))
  else
    bufnr = api.nvim_get_current_buf()
  end

  -- delete extmarks
  for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, constants.OCTO_EM_NS, 0, -1, {})) do
    api.nvim_buf_del_extmark(bufnr, constants.OCTO_EM_NS, m[1])
  end

  -- configure buffer
  api.nvim_buf_set_option(bufnr, "filetype", "octo_issue")
  api.nvim_buf_set_option(bufnr, "buftype", "acwrite")

  -- register issue
  api.nvim_buf_set_var(bufnr, "iid", iid)
  api.nvim_buf_set_var(bufnr, "number", number)
  api.nvim_buf_set_var(bufnr, "repo", repo)
  api.nvim_buf_set_var(bufnr, "state", state)
  api.nvim_buf_set_var(bufnr, "labels", obj.labels)
  api.nvim_buf_set_var(bufnr, "assignees", obj.assignees)
  api.nvim_buf_set_var(bufnr, "milestone", obj.milestone)
  api.nvim_buf_set_var(bufnr, "taggable_users", {obj.author.login})

  -- for pulls, store some additional info
  if obj.commits then
    api.nvim_buf_set_var(
      bufnr,
      "pr",
      {
        isDraft = obj.isDraft,
        merged = obj.merged,
        headRefName = obj.headRefName,
        baseRepoName = obj.baseRepository.nameWithOwner
      }
    )
  end

  -- buffer mappings
  M.apply_buffer_mappings(bufnr, type)

  -- write title
  M.write_title(bufnr, obj.title, 1)

  -- write details in buffer
  M.write_details(bufnr, obj)

  -- write issue/pr status
  M.write_state(bufnr, state:upper(), number)

  -- write body
  M.write_body(bufnr, obj)

  -- write body reactions
  local reaction_line = M.write_reactions(bufnr, obj.reactions, api.nvim_buf_line_count(bufnr) - 1)
  api.nvim_buf_set_var(bufnr, "body_reactions", obj.reactions)
  api.nvim_buf_set_var(bufnr, "body_reaction_line", reaction_line)

  -- write issue comments
  api.nvim_buf_set_var(bufnr, "comments", {})
  for _, c in ipairs(obj.comments.nodes) do
    M.write_comment(bufnr, c)
  end

  async_fetch_taggable_users(bufnr, repo, obj.participants.nodes)
  async_fetch_issues(bufnr, repo)

  -- show signs
  signs.render_signcolumn(bufnr)

  -- drop undo history
  vim.fn["octo#clear_history"]()

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)

  vim.cmd [[ augroup octo_buffer_autocmds ]]
  vim.cmd [[ au! * <buffer> ]]
  vim.cmd [[ au TextChanged <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ au TextChangedI <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ augroup END ]]
end

function M.save_issue()
  local bufnr = api.nvim_get_current_buf()
  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  local repo, number = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  -- collect comment metadata
  util.update_issue_metadata(bufnr)

  -- title & description
  if ft == "octo_issue" then
    local title_metadata = api.nvim_buf_get_var(bufnr, "title")
    local desc_metadata = api.nvim_buf_get_var(bufnr, "description")
    if title_metadata.dirty or desc_metadata.dirty then
      -- trust but verify
      if string.find(title_metadata.body, "\n") then
        api.nvim_err_writeln("Title can't contains new lines")
        return
      elseif title_metadata.body == "" then
        api.nvim_err_writeln("Title can't be blank")
        return
      end

      gh.run(
        {
          args = {
            "api",
            "-X",
            "PATCH",
            "-f",
            format("title=%s", title_metadata.body),
            "-f",
            format("body=%s", desc_metadata.body),
            format("repos/%s/issues/%s", repo, number)
          },
          cb = function(output)
            local resp = json.parse(output)

            if title_metadata.body == resp.title then
              title_metadata.saved_body = resp.title
              title_metadata.dirty = false
              api.nvim_buf_set_var(bufnr, "title", title_metadata)
            end

            if desc_metadata.body == resp.body then
              desc_metadata.saved_body = resp.body
              desc_metadata.dirty = false
              api.nvim_buf_set_var(bufnr, "description", desc_metadata)
            end

            signs.render_signcolumn(bufnr)
            print("Saved!")
          end
        }
      )
    end
  end

  -- comments
  local kind, post_url
  if ft == "octo_issue" then
    kind = "issues"
    post_url = format("repos/%s/%s/%d/comments", repo, kind, number)
  elseif ft == "octo_reviewthread" then
    kind = "pulls"
    local status, _, comment_id =
      string.find(api.nvim_buf_get_name(bufnr), "octo://.*/pull/%d+/reviewthread/.*/comment/(.*)")
    if not status then
      api.nvim_err_writeln("Cannot extract comment id from buffer name")
      return
    end
    post_url = format("/repos/%s/pulls/%d/comments/%s/replies", repo, number, comment_id)
  end

  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for _, metadata in ipairs(comments) do
    if metadata.body ~= metadata.saved_body then
      if metadata.id == -1 then
        -- create new comment/reply
        gh.run(
          {
            args = {
              "api",
              "-X",
              "POST",
              "-f",
              format("body=%s", metadata.body),
              post_url
            },
            cb = function(output, stderr)
              if stderr and not util.is_blank(stderr) then
                api.nvim_err_writeln(stderr)
              elseif output then
                local resp = json.parse(output)
                if vim.fn.trim(metadata.body) == vim.fn.trim(resp.body) then
                  for i, c in ipairs(comments) do
                    if tonumber(c.id) == -1 then
                      comments[i].id = resp.id
                      comments[i].saved_body = resp.body
                      comments[i].dirty = false
                      break
                    end
                  end
                  api.nvim_buf_set_var(bufnr, "comments", comments)
                  signs.render_signcolumn(bufnr)
                  print("Saved!")
                end
              end
            end
          }
        )
      else
        -- update comment/reply
        gh.run(
          {
            args = {
              "api",
              "-X",
              "PATCH",
              "-f",
              format("body=%s", metadata.body),
              format("repos/%s/%s/comments/%d", repo, kind, metadata.id)
            },
            cb = function(output, stderr)
              if stderr and not util.is_blank(stderr) then
                api.nvim_err_writeln(stderr)
              elseif output then
                local resp = json.parse(output)
                if vim.fn.trim(metadata.body) == vim.fn.trim(resp.body) then
                  for i, c in ipairs(comments) do
                    if tonumber(c.id) == tonumber(resp.id) then
                      comments[i].saved_body = resp.body
                      comments[i].dirty = false
                      break
                    end
                  end
                  api.nvim_buf_set_var(bufnr, "comments", comments)
                  signs.render_signcolumn(bufnr)
                  print("Saved!")
                end
              end
            end
          }
        )
      end
    end
  end

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)
end

function M.apply_buffer_mappings(bufnr, kind)
  local mapping_opts = {script = true, silent = true, noremap = true}

  if kind == "issue" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ic",
      [[<cmd>lua require'octo.commands'.change_issue_state('closed')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>io",
      [[<cmd>lua require'octo.commands'.change_issue_state('open')<CR>]],
      mapping_opts
    )

    local repo_ok, repo = pcall(api.nvim_buf_get_var, bufnr, "repo")
    if repo_ok then
      api.nvim_buf_set_keymap(
        bufnr,
        "n",
        "<space>il",
        format("<cmd>lua require'octo.menu'.issues('%s')<CR>", repo),
        mapping_opts
      )
    end
  end

  if kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>po",
      [[<cmd>lua require'octo.commands'.checkout_pr()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(bufnr, "n", "<space>pc", [[<cmd>lua require'octo.menu'.commits()<CR>]], mapping_opts)
    api.nvim_buf_set_keymap(bufnr, "n", "<space>pf", [[<cmd>lua require'octo.menu'.files()<CR>]], mapping_opts)
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>pd",
      [[<cmd>lua require'octo.commands'.show_pr_diff()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>pm",
      [[<cmd>lua require'octo.commands'.merge_pr("commit")<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>va",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'reviewers')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>vd",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'reviewers')<CR>]],
      mapping_opts
    )
  end

  if kind == "issue" or kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>la",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'labels')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ld",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'labels')<CR>]],
      mapping_opts
    )

    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>aa",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'assignees')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ad",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'assignees')<CR>]],
      mapping_opts
    )
  end

  if kind == "issue" or kind == "pull" or kind == "reviewthread" then
    -- autocomplete
    api.nvim_buf_set_keymap(bufnr, "i", "@", "@<C-x><C-o>", mapping_opts)
    api.nvim_buf_set_keymap(bufnr, "i", "#", "#<C-x><C-o>", mapping_opts)

    -- navigation
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>gi",
      [[<cmd>lua require'octo.navigation'.go_to_issue()<CR>]],
      mapping_opts
    )

    -- comments
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ca",
      [[<cmd>lua require'octo.commands'.add_comment()<CR>]],
      mapping_opts
    )

    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>cd",
      [[<cmd>lua require'octo.commands'.delete_comment()<CR>]],
      mapping_opts
    )

    -- reactions
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rp",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'hooray')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rh",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'heart')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>re",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'eyes')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>r+",
      [[<cmd>lua require'octo.commands'.reaction_action('add', '+1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>r-",
      [[<cmd>lua require'octo.commands'.reaction_action('add', '-1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rr",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'rocket')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rl",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'laugh')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rc",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'confused')<CR>]],
      mapping_opts
    )
  end
end

return M
