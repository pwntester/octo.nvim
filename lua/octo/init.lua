local gh = require("octo.gh")
local signs = require("octo.signs")
local hl = require("octo.highlights")
local constants = require("octo.constants")
local util = require "octo.util"
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

local function write_block(lines, opts)
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
  local title_mark = write_block({title, ""}, {bufnr = bufnr, mark = true, line = line})
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

function M.write_state(bufnr)
  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_TITLE_VT_NS, 0, -1)

  -- title virtual text
  local state = api.nvim_buf_get_var(bufnr, "state"):upper()
  local title_vt = {
    {tostring(api.nvim_buf_get_var(bufnr, "number")), "OctoNvimIssueId"},
    {format(" [%s] ", state), format("OctoNvimIssue%s", state)}
  }

  -- PR virtual text
  local status, pr = pcall(api.nvim_buf_get_var, bufnr, "pr")
  if status and pr then
    if pr.draft then
      table.insert(title_vt, {"[DRAFT] ", "OctoNvimIssueId"})
    end
    if pr.merged then
      table.insert(title_vt, {"[MERGED]", "OctoNvimIssueId"})
    end
  end
  api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_TITLE_VT_NS, 0, title_vt, {})
end

function M.write_description(bufnr, issue, line)
  local body = issue.body
  if vim.startswith(body, constants.NO_BODY_MSG) then
    body = " "
  end
  local description = string.gsub(body, "\r\n", "\n")
  local desc_mark = write_block(description, {bufnr = bufnr, mark = true, trailing_lines = 3, line = line})
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
  line = line or api.nvim_buf_line_count(bufnr) - 1
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, line + 1)
  if reactions.total_count > 0 then
    local reactions_vt = {}
    for reaction, count in pairs(reactions) do
      local emoji = require "octo.util".reaction_map[reaction]
      if emoji and count > 0 then
        table.insert(reactions_vt, {"", "OctoNvimBubble1"})
        table.insert(reactions_vt, {emoji, "OctoNvimBubble2"})
        table.insert(reactions_vt, {"", "OctoNvimBubble1"})
        table.insert(reactions_vt, {format(" %s ", count), "Normal"})
      end
    end
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_REACTIONS_VT_NS, line - 1, reactions_vt, {})
    return line
  end
end

function M.write_details(bufnr, issue, line)
  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_DETAILS_VT_NS, 0, -1)

  local details = {}

  -- author
  local author_vt = {
    {"Created by: ", "OctoNvimDetailsLabel"},
    {issue.user.login, "OctoNvimDetailsValue"}
  }
  table.insert(details, author_vt)

  -- created_at
  local created_at_vt = {
    {"Created at: ", "OctoNvimDetailsLabel"},
    {util.format_date(issue.created_at), "OctoNvimDetailsValue"}
  }
  table.insert(details, created_at_vt)

  if issue.state == "closed" then
    -- closed_at
    local closed_at_vt = {
      {"Closed at: ", "OctoNvimDetailsLabel"},
      {util.format_date(issue.closed_at), "OctoNvimDetailsValue"}
    }
    table.insert(details, closed_at_vt)
  else
    -- updated_at
    local updated_at_vt = {
      {"Updated at: ", "OctoNvimDetailsLabel"},
      {util.format_date(issue.updated_at), "OctoNvimDetailsValue"}
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
  if issue.labels and #issue.labels > 0 then
    for _, label in ipairs(issue.labels) do
      table.insert(labels_vt, {"", hl.create_highlight(label.color, {mode = "foreground"})})
      table.insert(labels_vt, {label.name, hl.create_highlight(label.color, {})})
      table.insert(labels_vt, {"", hl.create_highlight(label.color, {mode = "foreground"})})
      table.insert(labels_vt, {" ", "OctoNvimDetailsLabel"})
    end
  else
    table.insert(labels_vt, {"None yet", "OctoNvimMissingDetails"})
  end
  table.insert(details, labels_vt)

  if issue.pull_request then
    local url = issue.pull_request.url
    local segments = vim.split(url, "/")
    local owner = segments[5]
    local repo = segments[6]
    local pr_id = segments[8]
    local response =
      gh.run(
      {
        args = {"api", format("repos/%s/%s/pulls/%d", owner, repo, pr_id)},
        mode = "sync"
      }
    )
    local pr = json.parse(response)
    api.nvim_buf_set_var(bufnr, "pr", pr)

    -- requested reviewers
    local requested_reviewers_vt = {
      {"Requested Reviewers: ", "OctoNvimDetailsLabel"}
    }
    if pr.requested_reviewers and #pr.requested_reviewers > 0 then
      for i, as in ipairs(pr.requested_reviewers) do
        table.insert(requested_reviewers_vt, {as.login, "OctoNvimDetailsValue"})
        if i ~= #issue.assignees then
          table.insert(requested_reviewers_vt, {", ", "OctoNvimDetailsLabel"})
        end
      end
    else
      table.insert(requested_reviewers_vt, {"No requested reviewers", "OctoNvimMissingDetails"})
    end
    table.insert(details, requested_reviewers_vt)

    -- reviewers
    local reviewers_vt = {
      {"Reviewers: ", "OctoNvimDetailsLabel"}
    }
    if pr and #pr > 0 then
      for i, as in ipairs(pr) do
        table.insert(reviewers_vt, {format("%s (%s)", as.user.login, as.state), "OctoNvimDetailsValue"})
        if i ~= #issue.assignees then
          table.insert(reviewers_vt, {", ", "OctoNvimDetailsLabel"})
        end
      end
    else
      table.insert(reviewers_vt, {"No reviewers", "OctoNvimMissingDetails"})
    end
    table.insert(details, reviewers_vt)

    -- merged_by
    if pr.merged then
      local merged_by_vt = {
        {"Merged by: ", "OctoNvimDetailsLabel"},
        {pr.merged_by.login, "OctoNvimDetailsValue"}
      }
      table.insert(details, merged_by_vt)
    end

    -- from/into branches
    local branches_vt = {
      {"From: ", "OctoNvimDetailsLabel"},
      {pr.head.label, "OctoNvimDetailsValue"},
      {" Into: ", "OctoNvimDetailsLabel"},
      {pr.base.label, "OctoNvimDetailsValue"}
    }
    table.insert(details, branches_vt)

    -- changes
    local unit = (pr.additions + pr.deletions) / 4
    local additions = math.floor(0.5 + pr.additions / unit)
    local deletions = math.floor(0.5 + pr.deletions / unit)
    local changes_vt = {
      {"Commits: ", "OctoNvimDetailsLabel"},
      {tostring(pr.commits), "OctoNvimDetailsValue"},
      {" Changed files: ", "OctoNvimDetailsLabel"},
      {tostring(pr.changed_files), "OctoNvimDetailsValue"},
      {" (", "OctoNvimDetailsLabel"},
      {format("+%d ", pr.additions), "DiffAdd"},
      {format("-%d ", pr.deletions), "DiffDelete"}
    }
    if pr.additions > 0 then
      table.insert(changes_vt, {string.rep("■", additions), "DiffAdd"})
    end
    if pr.deletions > 0 then
      table.insert(changes_vt, {string.rep("■", deletions), "DiffDelete"})
    end
    table.insert(changes_vt, {"■", "DiffChange"})
    table.insert(changes_vt, {")", "OctoNvimDetailsLabel"})
    table.insert(details, changes_vt)
  end

  -- print empty #details + 2 lines
  line = line or api.nvim_buf_line_count(bufnr) + 1
  local empty_lines = {}
  for _ = 1, #details + 2, 1 do
    table.insert(empty_lines, "")
  end
  write_block(empty_lines, {bufnr = bufnr, mark = false, line = line})

  -- print details as virtual text
  for _, d in ipairs(details) do
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_DETAILS_VT_NS, line - 1, d, {})
    line = line + 1
  end
end

function M.write_comment(bufnr, comment, line)
  -- heading
  line = line or api.nvim_buf_line_count(bufnr) + 1
  write_block({"", ""}, {bufnr = bufnr, mark = false, line = line})
  local header_vt = {
    {format("On %s ", util.format_date(comment.created_at)), "OctoNvimCommentHeading"},
    {comment.user.login, "OctoNvimCommentUser"},
    {" commented", "OctoNvimCommentHeading"}
  }
  local comment_vt_ns = api.nvim_buf_set_virtual_text(bufnr, 0, line - 1, header_vt, {})

  -- body
  line = line + 2
  local comment_body = string.gsub(comment["body"], "\r\n", "\n")
  if vim.startswith(comment_body, constants.NO_BODY_MSG) then
    comment_body = " "
  end
  local content = vim.split(comment_body, "\n", true)
  vim.list_extend(content, {"", "", ""})
  local comment_mark = write_block(content, {bufnr = bufnr, mark = true, line = line})

  -- reactions
  line = line + #content
  local reaction_line = M.write_reactions(bufnr, comment.reactions, line - 2)

  -- update metadata
  local comments_metadata = api.nvim_buf_get_var(bufnr, "comments")
  table.insert(
    comments_metadata,
    {
      author = comment.user.login,
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

function M.load_issue()
  local bufname = vim.fn.bufname()
  local repo, number = string.match(bufname, "octo://(.+)/(%d+)")
  if not repo or not number then
    api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end

  gh.run(
    {
      args = {"api", format("repos/%s/issues/%s", repo, number)},
      cb = function(output)
        local issue = json.parse(output)
        if not issue.id and issue.message then
          api.nvim_err_writeln(issue.message)
          return
        end
        M.create_issue_buffer(issue, repo, false)
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
local function async_fetch_taggable_users(bufnr, repo)
  local users = api.nvim_buf_get_var(bufnr, "taggable_users") or {}
  local comments_metadata = api.nvim_buf_get_var(bufnr, "comments")
  for _, c in pairs(comments_metadata) do table.insert(users, c.author) end
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

function M.create_issue_buffer(issue, repo, create_buffer)
  if not issue["id"] then
    api.nvim_err_writeln(format("Cannot find issue in %s", repo))
    return
  end

  local iid = issue["id"]
  local number = issue["number"]
  local state = issue["state"]

  local bufnr
  if create_buffer then
    bufnr = api.nvim_create_buf(true, false)
    api.nvim_set_current_buf(bufnr)
    vim.cmd(format("file octo://%s/%d", repo, number))
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
  api.nvim_buf_set_var(bufnr, "labels", issue.labels)
  api.nvim_buf_set_var(bufnr, "assignees", issue.assignees)
  api.nvim_buf_set_var(bufnr, "milestone", issue.milestone)
  api.nvim_buf_set_var(bufnr, "taggable_users", {issue.user.login})

  -- local mappings
  local mapping_opts = {script = true, silent = true, noremap = true}

  api.nvim_buf_set_keymap(bufnr, "i", "@", "@<C-x><C-o>", mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "i", "#", "#<C-x><C-o>", mapping_opts)

  api.nvim_buf_set_keymap(bufnr, "n", "<space>gi", [[<cmd>lua require'octo.navigation'.go_to_issue()<CR>]], mapping_opts)

  api.nvim_buf_set_keymap(bufnr, "n", "<space>ca", [[<cmd>lua require'octo.commands'.add_comment()<CR>]], mapping_opts)

  api.nvim_buf_set_keymap(bufnr, "n", "<space>cd", [[<cmd>lua require'octo.commands'.delete_comment()<CR>]], mapping_opts)

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
  api.nvim_buf_set_keymap(bufnr, "n", "<space>il", format("<cmd>lua require'octo.menu'.issues('%s')<CR>", repo), mapping_opts)

  api.nvim_buf_set_keymap(bufnr, "n", "<space>co", [[<cmd>lua require'octo.commands'.checkout_pr()<CR>]], mapping_opts)

  api.nvim_buf_set_keymap(bufnr, "n", "<space>cm", [[<cmd>lua require'octo.menu'.commits()<CR>]], mapping_opts)

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

  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<space>va",
    [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'requested_reviewers')<CR>]],
    mapping_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<space>vd",
    [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'requested_reviewers')<CR>]],
    mapping_opts
  )

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

  -- write title
  M.write_title(bufnr, issue.title, 1)

  -- write details in buffer
  M.write_details(bufnr, issue, 3)

  -- write issue/pr status on line 1
  M.write_state(bufnr)

  -- write description
  M.write_description(bufnr, issue)

  -- write reactions
  local reaction_line = M.write_reactions(bufnr, issue.reactions)
  api.nvim_buf_set_var(bufnr, "reaction_line", reaction_line)
  api.nvim_buf_set_var(bufnr, "reactions", issue.reactions)

  -- write issue comments
  api.nvim_buf_set_var(bufnr, "comments", {})
  local comments_count = tonumber(issue["comments"])
  local comments_processed = 0
  if comments_count > 0 then
    gh.run(
      {
        args = {"api", format("repos/%s/issues/%d/comments", repo, number)},
        cb = function(response)
          local resp = json.parse(response)
          for _, c in ipairs(resp) do
            M.write_comment(bufnr, c)
            comments_processed = comments_processed + 1
          end
        end
      }
    )
  end

  local status =
    vim.wait(
    5000,
    function()
      return comments_processed == comments_count
    end,
    200
  )

  async_fetch_taggable_users(bufnr, repo)

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

function M.save_issue(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  if not vim.startswith(bufname, "octo://") then
    return
  end

  -- number
  local number = api.nvim_buf_get_var(bufnr, "number")

  -- repo
  local repo = api.nvim_buf_get_var(bufnr, "repo")
  if not repo then
    api.nvim_err_writeln("Buffer is not linked to a GitHub issue")
    return
  end

  -- collect comment metadata
  util.update_issue_metadata(bufnr)

  -- title & description
  local title_metadata = api.nvim_buf_get_var(bufnr, "title")
  local desc_metadata = api.nvim_buf_get_var(bufnr, "description")
  if title_metadata.dirty or desc_metadata.dirty then
    -- trust but verify
    if string.find(title_metadata["body"], "\n") then
      api.nvim_err_writeln("Title can't contains new lines")
      return
    elseif title_metadata["body"] == "" then
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
          format("title=%s", title_metadata["body"]),
          "-f",
          format("body=%s", desc_metadata["body"]),
          format("repos/%s/issues/%s", repo, number)
        },
        cb = function(output)
          local resp = json.parse(output)

          if title_metadata["body"] == resp["title"] then
            title_metadata["saved_body"] = resp["title"]
            title_metadata["dirty"] = false
            api.nvim_buf_set_var(bufnr, "title", title_metadata)
          end

          if desc_metadata["body"] == resp["body"] then
            desc_metadata["saved_body"] = resp["body"]
            desc_metadata["dirty"] = false
            api.nvim_buf_set_var(bufnr, "description", desc_metadata)
          end

          signs.render_signcolumn(bufnr)
          print("Saved!")
        end
      }
    )
  end

  -- comments
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for _, metadata in ipairs(comments) do
    if metadata["body"] ~= metadata["saved_body"] then
      gh.run(
        {
          args = {
            "api",
            "-X",
            "PATCH",
            "-f",
            format("body=%s", metadata["body"]),
            format("repos/%s/issues/comments/%s", repo, metadata["id"])
          },
          cb = function(output)
            local resp = json.parse(output)
            if metadata["body"] == resp["body"] then
              for i, c in ipairs(comments) do
                if c["id"] == resp["id"] then
                  comments[i]["saved_body"] = resp["body"]
                  comments[i]["dirty"] = false
                  break
                end
              end
              api.nvim_buf_set_var(bufnr, "comments", comments)
              signs.render_signcolumn(bufnr)
              print("Saved!")
            end
          end
        }
      )
    end
  end

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)
end

return M
