local constants = require "octo.constants"
local date = require "octo.date"
local popup = require "popup"
local base64 = require "octo.base64"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local format = string.format
local api = vim.api
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}
local repo_id_cache = {}

M.reaction_map = {
  ["THUMBS_UP"] = "👍",
  ["THUMBS_DOWN"] = "👎",
  ["LAUGH"] = "😀",
  ["HOORAY"] = "🎉",
  ["CONFUSED"] = "😕",
  ["HEART"] = "❤️",
  ["ROCKET"] = "🚀",
  ["EYES"] = "👀"
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
    if pr.baseRepoName ~= local_repo then
      api.nvim_err_writeln(format("Not in PR repo. Expected %s, got %s", pr.baseRepoName, local_repo))
      return false
    elseif pr.headRefName ~= local_branch then
      api.nvim_err_writeln(format("Not in PR branch. Expected %s, got %s", pr.headRefName, local_branch))
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

function M.update_reactions_at_cursor(bufnr, cursor, reactions) --, reaction_line)
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for i, comment in ipairs(comments) do
    local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_EM_NS, comment.extmark, {details = true})
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      --  cursor located in the body of a comment
      comments[i].reactions = reactions
      --print("DIFF", comments[i].reaction_line, reaction_line)
      --comments[i].reaction_line = reaction_line
      api.nvim_buf_set_var(bufnr, "comments", comments)
      return
    end
  end

  -- cursor not located at any comment, so updating issue
  api.nvim_buf_set_var(bufnr, "body_reactions", reactions)
  --api.nvim_buf_set_var(bufnr, "body_reaction_line", reaction_line)
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

function M.get_repo_id(repo)
  if repo_id_cache[repo] then
    return repo_id_cache[repo]
  else
    local owner = vim.split(repo, "/")[1]
    local name = vim.split(repo, "/")[2]
    local query = format(graphql.repository_id_query, owner, name)
    local output =
      gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        mode = "sync"
      }
    )
    local resp = json.parse(output)
    local id = resp.data.repository.id
    repo_id_cache[repo] = id
    return id
  end
end

function M.aggregate_pages(text, aggregation_key)
  -- aggregation key can be at any level (eg: comments)
  -- take the first response and extend it with elements from the
  -- subsequent responses

  local responses = vim.split(text, "}{")
  if #responses > 1 then
    responses[1] = responses[1] .. "}"
    for i = 2, #responses - 1 do
      responses[i] = "{" .. responses[i] .. "}"
    end
    responses[#responses] = "{" .. responses[#responses]

    local base_resp = json.parse(responses[1])
    local base_page = M.get_nested_prop(base_resp, aggregation_key)
    for i = 2, #responses do
      local paged_resp = json.parse(responses[i])
      local page = M.get_nested_prop(paged_resp, aggregation_key)
      vim.list_extend(base_page, page)
    end
    return base_resp
  else
    return json.parse(responses)
  end
end

function table.slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

function M.get_nested_prop(obj, prop)
  while true do
    local parts = vim.split(prop, "%.")
    if #parts == 1 then
      break
    else
      local part = parts[1]
      local remaining = table.concat(table.slice(parts, 2, #parts), ".")
      return M.get_nested_prop(obj[part], remaining)
    end
  end
  return obj[prop]
end

return M
