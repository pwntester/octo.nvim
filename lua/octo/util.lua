local constants = require "octo.constants"
local date = require "octo.date"
local base64 = require "octo.base64"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local format = string.format
local vim = vim
local api = vim.api
local json = {
  parse = vim.fn.json_decode
}

local M = {}
local repo_id_cache = {}

M.state_hl_map = {
  MERGED = "OctoNvimStateMerged",
  CLOSED = "OctoNvimStateClosed",
  OPEN = "OctoNvimStateOpen",
  APPROVED = "OctoNvimStateApproved",
  CHANGES_REQUESTED = "OctoNvimStateChangesRequested",
  COMMENTED = "OctoNvimStateCommented",
  DISMISSED = "OctoNvimStateDismissed",
  PENDING = "OctoNvimStatePending",
  REVIEW_REQUIRED = "OctoNvimStatePending"
}

M.state_icon_map = {
  MERGED = "⇌",
  CLOSED = "⚑",
  OPEN = "⚐",
  APPROVED = "✓",
  CHANGES_REQUESTED = "±",
  COMMENTED = "☷",
  DISMISSED = "",
  PENDING = "",
  REVIEW_REQUIRED = ""
}

M.state_message_map = {
  MERGED = "Merged",
  CLOSED = "Closed",
  OPEN = "Open",
  APPROVED = "Approved",
  CHANGES_REQUESTED = "Changes requested",
  COMMENTED = "Has review comments",
  DISMISSED = "Dismissed",
  PENDING = "Awaiting required review",
  REVIEW_REQUIRED = "Awaiting required review"
}

function M.calculate_strongest_review_state(states)
  if vim.tbl_contains(states, "APPROVED") then
    return "APPROVED"
  elseif vim.tbl_contains(states, "CHANGES_REQUESTED") then
    return "CHANGES_REQUESTED"
  elseif vim.tbl_contains(states, "COMMENTED") then
    return "COMMENTED"
  elseif vim.tbl_contains(states, "PENDING") then
    return "PENDING"
  elseif vim.tbl_contains(states, "REVIEW_REQUIRED") then
    return "REVIEW_REQUIRED"
  end
end

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

function M.tbl_slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

function table.pack(...)
  return {n = select("#", ...), ...}
end

function M.is_blank(s)
  return not (s ~= nil and string.match(s, "%S") ~= nil)
end

function M.get_remote_name()
  local candidates = vim.g.octo_default_remote
  for _, candidate in ipairs(candidates) do
    local cmd = format("git config --get remote.%s.url", candidate)
    local url = string.gsub(vim.fn.system(cmd), "%s+", "")
    if not M.is_blank(url) then
      local owner, name
      if #vim.split(url, "://") == 2 then
        owner = vim.split(url, "/")[#vim.split(url, "/") - 1]
        name = string.gsub(vim.split(url, "/")[#vim.split(url, "/")], ".git$", "")
      elseif #vim.split(url, "@") == 2 then
        local segment = vim.split(url, ":")[2]
        owner = vim.split(segment, "/")[1]
        name = string.gsub(vim.split(segment, "/")[2], ".git$", "")
      end
      return format("%s/%s", owner, name)
    end
  end
end

function M.in_pr_repo()
  local bufname = api.nvim_buf_get_name(0)
  if not vim.startswith(bufname, "octo://") then
    api.nvim_err_writeln("Not in Octo buffer")
    return
  end
  local status, pr = pcall(api.nvim_buf_get_var, 0, "pr")
  if status and pr then
    local local_repo = M.get_remote_name()
    if pr.baseRepoName ~= local_repo then
      api.nvim_err_writeln(format("Not in PR repo. Expected %s, got %s", pr.baseRepoName, local_repo))
      return false
    else
      return true
    end
  else
    api.nvim_err_writeln("Not in Octo PR buffer")
    return
  end
  return false
end

function M.in_pr_branch()
  local bufname = api.nvim_buf_get_name(0)
  if not vim.startswith(bufname, "octo://") then
    return
  end
  local status, pr = pcall(api.nvim_buf_get_var, 0, "pr")
  if status and pr then
    -- only works with Git 2.22 and above
    -- local cmd = "git branch --show-current"
    local cmd = "git rev-parse --abbrev-ref HEAD"
    local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")
    if local_branch == format("%s/%s", pr.headRepoName, pr.headRefName) then
      -- for PRs submitted from master, local_branch will get something like other_repo/master
      local_branch = vim.split(local_branch, "/")[2]
    end
    local local_repo = M.get_remote_name()
    if pr.baseRepoName ~= local_repo then
      api.nvim_err_writeln(format("Not in PR repo. Expected %s, got %s", pr.baseRepoName, local_repo))
      return false
    elseif pr.headRefName ~= local_branch then
      -- TODO: suggest to checkout the branch
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
  local status, lines = pcall(api.nvim_buf_get_lines, bufnr, start_line, end_line + 1, true)
  if status and lines then
    local text = vim.fn.join(lines, "\n")
    return start_line, end_line, text
  end
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
    mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, {details = true})
    start_line, end_line, text = M.get_extmark_region(bufnr, mark)
    M.update_metadata(metadata, start_line, end_line, text)
    api.nvim_buf_set_var(bufnr, "title", metadata)

    -- description
    metadata = api.nvim_buf_get_var(bufnr, "description")
    mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, {details = true})
    start_line, end_line, text = M.get_extmark_region(bufnr, mark)
    if text == "" then
      -- description has been removed
      -- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
      api.nvim_buf_set_lines(bufnr, start_line, start_line + 1, false, {" ", ""})
      api.nvim_win_set_cursor(0, {start_line + 1, 0})
    end
    M.update_metadata(metadata, start_line, end_line, text)
    api.nvim_buf_set_var(bufnr, "description", metadata)
  end

  -- comments
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for i, m in ipairs(comments) do
    metadata = m
    mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, {details = true})
    start_line, end_line, text = M.get_extmark_region(bufnr, mark)

    if text == "" then
      -- comment has been removed
      -- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
      api.nvim_buf_set_lines(bufnr, start_line, start_line + 1, false, {" ", ""})
      api.nvim_win_set_cursor(0, {start_line + 1, 0})
    end

    M.update_metadata(metadata, start_line, end_line, text)
    comments[i] = metadata
  end
  api.nvim_buf_set_var(bufnr, "comments", comments)
end

function M.get_comment_at_cursor(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for _, comment in ipairs(comments) do
    local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, comment.extmark, {details = true})
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      return comment, start_line, end_line
    end
  end
  return nil
end

function M.get_thread_at_cursor(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  if vim.bo[bufnr].ft == "octo_issue" then
    local thread_map = api.nvim_buf_get_var(bufnr, "reviewThreadMap")
    local marks = api.nvim_buf_get_extmarks(bufnr, constants.OCTO_THREAD_NS, 0, -1, {details = true})
    for _, mark in ipairs(marks) do
      local info = thread_map[tostring(mark[1])]
      if not info then
        goto continue
      end
      local thread_id = info.thread_id
      local first_comment_id = info.first_comment_id
      local start_line = mark[2]
      local end_line = mark[4]["end_row"]
      if start_line <= cursor[1] and end_line >= cursor[1] then
        return thread_id, start_line, end_line, first_comment_id
      end
      ::continue::
    end
  elseif vim.bo[bufnr].ft == "octo_reviewthread" then
    local bufname = api.nvim_buf_get_name(bufnr)
    local thread_id, first_comment_id = string.match(bufname, "octo://.*/pull/%d+/reviewthread/(.*)/comment/(.*)")
    local end_line = api.nvim_buf_line_count(bufnr) - 1
    return thread_id, 1, end_line, first_comment_id
  end
  return nil
end

function M.update_reactions_at_cursor(bufnr, reaction_groups, reaction_line)
  local cursor = api.nvim_win_get_cursor(0)
  local reactions_count = 0
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count  + 1
    end
  end

  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for i, comment in ipairs(comments) do
    local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, comment.extmark, {details = true})
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      --  cursor located in the body of a comment
      --  update reaction groups
      comments[i].reaction_groups = reaction_groups

      -- update reaction line
      if not comments[i].reaction_line and reactions_count > 0 then
        comments[i].reaction_line = reaction_line
      elseif reactions_count == 0 then
        comments[i].reaction_line = nil
      end

      -- update comments
      api.nvim_buf_set_var(bufnr, "comments", comments)
      return
    end
  end

  -- cursor not located at any comment, so updating issue
  --  update reaction groups
  api.nvim_buf_set_var(bufnr, "body_reaction_groups", reaction_groups)
  local body_reaction_line = api.nvim_buf_get_var(bufnr, "body_reaction_line")
  if not body_reaction_line and reactions_count > 0 then
    api.nvim_buf_set_var(bufnr, "body_reaction_line", reaction_line)
  elseif reactions_count == 0 then
    api.nvim_buf_set_var(bufnr, "body_reaction_line", nil)
  end
end

function M.format_date(date_string)
  local time_bias = date():getbias() * -1
  return date(date_string):addminutes(time_bias):fmt(vim.g.octo_date_format)
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
    local owner, name = M.split_repo(repo)
    local query = graphql("repository_id_query", owner, name)
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

function M.get_pages(text)
  local responses = {}
  while true do
    local idx = string.find(text, '}{"data"')
    if not idx then
      table.insert(responses, json.parse(text))
      break
    end
    local resp = string.sub(text, 0, idx)
    table.insert(responses, json.parse(resp))
    text = string.sub(text, idx + 1)
  end
  return responses
end

function M.aggregate_pages(text, aggregation_key)
  -- aggregation key can be at any level (eg: comments)
  -- take the first response and extend it with elements from the
  -- subsequent responses
  local responses = M.get_pages(text)
  local base_resp = responses[1]
  if #responses > 1 then
    local base_page = M.get_nested_prop(base_resp, aggregation_key)
    for i = 2, #responses do
      local extra_page = M.get_nested_prop(responses[i], aggregation_key)
      vim.list_extend(base_page, extra_page)
    end
  end
  return base_resp
end

function M.get_nested_prop(obj, prop)
  while true do
    local parts = vim.split(prop, "%.")
    if #parts == 1 then
      break
    else
      local part = parts[1]
      local remaining = table.concat(M.tbl_slice(parts, 2, #parts), ".")
      return M.get_nested_prop(obj[part], remaining)
    end
  end
  return obj[prop]
end

function M.escape_chars(string)
  return string.gsub(
    string,
    '["\\]',
    {
      ['"'] = '\\"',
      ['\\'] = '\\\\',
    }
  )
end

function M.get_repo_number_from_varargs(...)
  local repo, number
  local args = table.pack(...)
  if args.n == 0 then
    print("[Octo] Missing arguments")
    return
  elseif args.n == 1 then
    repo = M.get_remote_name()
    number = tonumber(args[1])
  elseif args.n == 2 then
    repo = args[1]
    number = tonumber(args[2])
  else
    print("[Octo] Unexpected arguments")
    return
  end
  if not repo then
    print("[Octo] Cant find repo name")
    return
  end
  if not number then
    print("[Octo] Missing issue/pr number")
    return
  end
  return repo, number
end

function M.get_issue(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  vim.cmd(format("edit octo://%s/issue/%s", repo, number))
end

function M.get_pull_request(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  vim.cmd(format("edit octo://%s/pull/%s", repo, number))
end

function M.parse_url(url)
  local repo, kind, number = string.match(url, constants.URL_ISSUE_PATTERN)
  if repo and number and kind == "issues" then
    return repo, number, "issue"
  elseif repo and number and kind == "pull" then
    return repo, number, kind
  end
end

function M.get_file_contents(repo, commit, path, cb)
  local owner, name = M.split_repo(repo)
  local query = graphql("file_content_query", owner, name, commit, path)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not M.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local blob = resp.data.repository.object
          local lines = {}
          if blob and blob ~= vim.NIL then
            lines = vim.split(blob.text, "\n")
          end
          cb(lines)
        end
      end
    }
  )
end

function M.set_timeout(delay, callback, ...)
  local timer = vim.loop.new_timer()
  local args = {...}
  vim.loop.timer_start(
    timer,
    delay,
    0,
    function()
      vim.loop.timer_stop(timer)
      vim.loop.close(timer)
      callback(unpack(args))
    end
  )
  return timer
end

function M.getwin4buf(bufnr)
  local tabpage = api.nvim_get_current_tabpage()
  local wins = api.nvim_tabpage_list_wins(tabpage)
  for _, w in ipairs(wins) do
    if bufnr == api.nvim_win_get_buf(w) then
      return w
    end
  end
  return -1
end

function M.cursor_in_col_range(start_col, end_col)
  local cursor = api.nvim_win_get_cursor(0)
  if start_col and end_col then
    if start_col <= cursor[2] and cursor[2] <= end_col then
      return true
    end
  end
  return false
end

function M.split_repo(repo)
  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  return owner, name
end

function M.reactions_at_cursor()
  local bufnr = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local ok_body, body_reaction_line = pcall(api.nvim_buf_get_var, bufnr, "body_reaction_line")
  if ok_body and body_reaction_line and body_reaction_line == cursor[1] then
    return api.nvim_buf_get_var(bufnr, "iid")
  end

  local ok_comments, comments_metadata = pcall(api.nvim_buf_get_var, bufnr, "comments")
  if ok_comments and comments_metadata then
    for _, c in pairs(comments_metadata) do
      if c.reaction_line and c.reaction_line == cursor[1] then
        return c.id
      end
    end
  end
  return nil
end

function M.extract_pattern_at_cursor(pattern)
  local current_line = vim.fn.getline(".")
  if current_line:find(pattern) then
    local res = table.pack(current_line:find(pattern))
    local start_col = res[1]
    local end_col = res[2]
    if M.cursor_in_col_range(start_col, end_col) then
      return unpack(M.tbl_slice(res, 3, #res))
    end
  end
end

function M.pattern_split(str, pattern)
  -- https://gist.github.com/boredom101/0074f1af6bd5cd6c7848ac6af3e88e85
  local words = {}
  for word in str:gmatch(pattern) do
    words[#words+1] = word
  end
  return words
end

function M.text_wrap(text, width)
  -- https://gist.github.com/boredom101/0074f1af6bd5cd6c7848ac6af3e88e85

  width = width or math.floor((vim.fn.winwidth(0) * 3) / 4)
  local lines = M.pattern_split(text, "[^\r\n]+")
  local widthLeft
  local result = {}
  local line = {}

  -- Insert each source line into the result, one-by-one
  for k=1, #lines do
    local sourceLine = lines[k]
    widthLeft = width -- all the width is left
    local words = M.pattern_split(sourceLine, "%S+")
    for l=1, #words do
      local word = words[l]
      -- If the word is longer than an entire line:
      if #word > width then
        -- In case the word is longer than multible lines:
        while (#word > width) do
          -- Fit as much as possible
          table.insert(line, word:sub(0, widthLeft))
          table.insert(result, table.concat(line, " "))

          -- Take the rest of the word for next round
          word = word:sub(widthLeft + 1)
          widthLeft = width
          line = {}
        end

        -- The rest of the word that could share a line
        line = {word}
        widthLeft = width - (#word + 1)

      -- If we have no space left in the current line
      elseif (#word + 1) > widthLeft then
        table.insert(result, table.concat(line, " "))

        -- start next line
        line = {word}
        widthLeft = width - (#word + 1)

      -- if we could fit the word on the line
      else
        table.insert(line, word)
        widthLeft = widthLeft - (#word + 1)
      end
    end

    -- Insert the rest of the source line
    table.insert(result, table.concat(line, " "))
    line = {}
  end
  return result
end

function M.count_reactions(reaction_groups)
  local reactions_count = 0
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count  + 1
    end
  end
  return reactions_count
end

return M
