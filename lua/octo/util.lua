local constants = require "octo.constants"
local date = require "octo.date"
local popup = require "popup"
local base64 = require "octo.base64"
local format = string.format
local api = vim.api

local M = {}

M.reaction_map = {
  ["+1"] = "👍",
  ["-1"] = "👎",
  ["laugh"] = "😀",
  ["hooray"] = "🎉",
  ["confused"] = "😕",
  ["heart"] = "❤️",
  ["rocket"] = "🚀",
  ["eyes"] = "👀"
}

function M.is_blank(s)
  return not (s ~= nil and s:match("%S") ~= nil)
end

function M.get_remote_name(remote)
  remote = remote or "origin"
  local cmd = format("git config --get remote.%s.url", remote)
  local url = string.gsub(vim.fn.system(cmd), "%s+", "")
  local owner, repo
  if #vim.split(url, "://") == 2 then
    owner = vim.split(url, "/")[#vim.split(url, "/") - 1]
    repo = string.gsub(vim.split(url, "/")[#vim.split(url, "/")], ".git$", "")
  elseif #vim.split(url, "@") == 2 then
    local segment = vim.split(url, ":")[2]
    owner = vim.split(segment, "/")[1]
    repo = string.gsub(vim.split(segment, "/")[2], ".git$", "")
  end
  return format("%s/%s", owner, repo)
end

function M.in_pr_branch()
  local bufname = api.nvim_buf_get_name(0)
  if not vim.startswith(bufname, "octo://") then
    return
  end
  local status, pr = pcall(api.nvim_buf_get_var, 0, "pr")
  if status and pr then
    local cmd = "git branch --show-current"
    local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")
    local local_repo = M.get_remote_name()
    if pr.base.repo.full_name ~= local_repo then
      api.nvim_err_writeln(format("Not in PR repo. Expected %s, got %s", pr.base.repo.full_name, local_repo))
      return false
    elseif pr.head.ref ~= local_branch then
      api.nvim_err_writeln(format("Not in PR branch. Expected %s, got %s", pr.head.ref, local_branch))
      return false
    end
    return true
  end
  return false
end

-- TODO: we need a better name for this
function M.get_repo_number(filetypes)
  local bufnr = api.nvim_get_current_buf()
  filetypes = filetypes or {"octo_issue"}
  if not vim.tbl_contains(filetypes, vim.bo.ft) then
    api.nvim_err_writeln(
      format("Not in correct octo buffer. Expected any of %s, got %s", vim.inspect(filetypes), vim.bo.ft)
    )
    return
  end

  local number_ok, number = pcall(api.nvim_buf_get_var, bufnr, "number")
  if not number_ok then
    api.nvim_err_writeln("Missing octo metadata")
    return
  end
  local repo_ok, repo = pcall(api.nvim_buf_get_var, bufnr, "repo")
  if not repo_ok then
    api.nvim_err_writeln("Missing octo metadata")
    return
  end
  return repo, number
end

function M.get_repo_number_pr()
  local repo, number = M.get_repo_number()
  if not repo then
    return
  end
  local bufnr = api.nvim_get_current_buf()
  local pr_ok, pr = pcall(api.nvim_buf_get_var, bufnr, "pr")
  if not pr_ok then
    api.nvim_err_writeln("Not PR buffer")
    return nil
  end
  return repo, number, pr
end

function M.get_extmark_region(bufnr, mark)
  -- extmarks are placed on
  -- start line - 1 (except for line 0)
  -- end line + 2
  local start_line = mark[1] + 1
  if start_line == 1 then
    start_line = 0
  end
  local end_line = mark[3]["end_row"] - 2
  if start_line > end_line then
    end_line = start_line
  end
  -- Indexing is zero-based, end-exclusive, so adding 1 to end line
  local lines = api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, true)
  local text = vim.fn.join(lines, "\n")
  return start_line, end_line, text
end

function M.update_metadata(metadata, start_line, end_line, text)
  metadata["start_line"] = start_line
  metadata["end_line"] = end_line
  if vim.fn.trim(text) ~= vim.fn.trim(metadata["saved_body"]) then
    metadata["dirty"] = true
  else
    metadata["dirty"] = false
  end
  metadata["body"] = text
end

function M.update_issue_metadata(bufnr)
  local mark, text, start_line, end_line, metadata

  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  if ft == "octo_issue" then
    -- title
    metadata = api.nvim_buf_get_var(bufnr, "title")
    mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_EM_NS, metadata.extmark, {details = true})
    start_line, end_line, text = M.get_extmark_region(bufnr, mark)
    M.update_metadata(metadata, start_line, end_line, text)
    api.nvim_buf_set_var(bufnr, "title", metadata)

    -- description
    metadata = api.nvim_buf_get_var(bufnr, "description")
    mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_EM_NS, metadata.extmark, {details = true})
    start_line, end_line, text = M.get_extmark_region(bufnr, mark)
    if text == "" then
      -- description has been removed
      -- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
      api.nvim_buf_set_lines(bufnr, start_line, start_line + 1, false, {" ", ""})
      local winnr = api.nvim_get_current_win()
      api.nvim_win_set_cursor(winnr, {start_line + 1, 0})
    end
    M.update_metadata(metadata, start_line, end_line, text)
    api.nvim_buf_set_var(bufnr, "description", metadata)
  end

  -- comments
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for i, m in ipairs(comments) do
    metadata = m
    mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_EM_NS, metadata.extmark, {details = true})
    start_line, end_line, text = M.get_extmark_region(bufnr, mark)

    if text == "" then
      -- comment has been removed
      -- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
      api.nvim_buf_set_lines(bufnr, start_line, start_line + 1, false, {" ", ""})
      local winnr = api.nvim_get_current_win()
      api.nvim_win_set_cursor(winnr, {start_line + 1, 0})
    end

    M.update_metadata(metadata, start_line, end_line, text)
    comments[i] = metadata
  end
  api.nvim_buf_set_var(bufnr, "comments", comments)
end

function M.get_comment_at_cursor(bufnr, cursor)
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  --local cursor = api.nvim_win_get_cursor(0)
  for _, comment in ipairs(comments) do
    local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_EM_NS, comment.extmark, {details = true})
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      return {comment, start_line, end_line}
    end
  end
  return nil
end

function M.update_reactions_at_cursor(bufnr, cursor, reactions, reaction_line)
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for i, comment in ipairs(comments) do
    local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_EM_NS, comment.extmark, {details = true})
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      --  cursor located in the body of a comment
      comments[i].reactions = reactions
      comments[i].reaction_line = reaction_line
      api.nvim_buf_set_var(bufnr, "comments", comments)
      return
    end
  end

  -- cursor not located at any comment, so updating issue
  api.nvim_buf_set_var(bufnr, "reactions", reactions)
  api.nvim_buf_set_var(bufnr, "reaction_line", reaction_line)
end

function M.format_date(date_string)
  local time_bias = date():getbias() * -1
  return date(date_string):addminutes(time_bias):fmt(vim.g.octo_date_format)
end

function M.create_content_popup(lines)
  local max_line = -1
  for _, line in ipairs(lines) do
    max_line = math.max(#line, max_line)
  end
  local line_count = vim.o.lines - vim.o.cmdheight
  local max_width = math.min(vim.o.columns * 0.9, max_line)
  if vim.o.laststatus ~= 0 then
    line_count = line_count - 1
  end
  local winnr, _ =
    popup.create(
    lines,
    {
      line = (line_count - #lines) / 2,
      col = (vim.o.columns - max_width) / 2,
      minwidth = 40,
      border = {1, 1, 1, 1},
      borderchars = {"─", "│", "─", "│", "┌", "┐", "┘", "└"},
      padding = {0, 1, 0, 1}
    }
  )
  local bufnr = api.nvim_win_get_buf(winnr)
  local mapping_opts = {script = true, silent = true, noremap = true}
  api.nvim_buf_set_keymap(bufnr, "n", "q", format(":call nvim_win_close(%d, 1)<CR>", winnr), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<esc>", format(":call nvim_win_close(%d, 1)<CR>", winnr), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-c>", format(":call nvim_win_close(%d, 1)<CR>", winnr), mapping_opts)
  return winnr, bufnr
end

function M.get_buffer_kind(bufnr)
  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  local kind
  if ft == "octo_issue" then
    kind = "issues"
  elseif ft == "octo_reviewthread" then
    kind = "pulls"
  end
  return kind
end

function M.graph2rest(id)
  local decoded = base64.decode(id)
  local _, _, rest_id = string.find(decoded, "(%d+)$")
  return rest_id
end

function M.convert_reactions(v4_reactions)
  local v3_reactions = {
    ["+1"] = 0,
    ["-1"] = 0,
    ["laugh"] = 0,
    ["hooray"] = 0,
    ["confused"] = 0,
    ["heart"] = 0,
    ["rocket"] = 0,
    ["eyes"] = 0
  }
  v3_reactions.url = v4_reactions.url
  v3_reactions.total_count = v4_reactions.totalCount
  for _, reaction in ipairs(v4_reactions.nodes) do
    if string.upper(reaction.content) == "THUMBS_UP" then
      reaction.content = "+1"
    elseif string.upper(reaction.content) == "THUMBS_DOWN" then
      reaction.content = "-1"
    end
    v3_reactions[string.lower(reaction.content)] = v3_reactions[string.lower(reaction.content)] + 1
  end
  return v3_reactions
end

return M
