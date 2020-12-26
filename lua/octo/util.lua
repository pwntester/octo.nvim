local constants = require("octo.constants")
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
    print("pr head", pr.head.ref, pr.head.repo.full_name)
    print("pr base", pr.base.ref, pr.base.repo.full_name)
    print("local", local_branch, local_repo)
  end
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

return M
