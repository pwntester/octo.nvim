local constants = require "octo.constants"
local date = require "octo.date"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local config = require "octo.config"
local _, Job = pcall(require, "plenary.job")

local M = {}

local repo_id_cache = {}
local path_sep = package.config:sub(1, 1)

M.viewed_state_map = {
  DISMISSED = { icon = " ", hl = "OctoRed" },
  VIEWED = { icon = "﫟", hl = "OctoGreen" },
  UNVIEWED = { icon = " ", hl = "OctoBlue" },
}

M.state_msg_map = {
  APPROVED = "approved",
  CHANGES_REQUESTED = "requested changes",
  COMMENTED = "commented",
  DISMISSED = "dismissed",
  PENDING = "pending",
}

M.state_hl_map = {
  MERGED = "OctoStateMerged",
  CLOSED = "OctoStateClosed",
  OPEN = "OctoStateOpen",
  APPROVED = "OctoStateApproved",
  CHANGES_REQUESTED = "OctoStateChangesRequested",
  COMMENTED = "OctoStateCommented",
  DISMISSED = "OctoStateDismissed",
  PENDING = "OctoStatePending",
  REVIEW_REQUIRED = "OctoStatePending",
  SUBMITTED = "OctoStateSubmitted",

  OPENED = "OctoStateOpen",
  ACTIVE = "OctoStateActive",
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
  REVIEW_REQUIRED = "",
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
  REVIEW_REQUIRED = "Awaiting required review",

  ACTIVE = "Open",
  CLOSE = "Closed",
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
  ["EYES"] = "👀",
}

function M.tbl_soft_extend(a, b)
  for k, v in pairs(a) do
    if type(v) ~= "table" then
      if b[k] ~= nil then
        a[k] = b[k]
      end
    end
  end
end

function M.tbl_deep_clone(t)
  if not t then
    return
  end
  local clone = {}

  for k, v in pairs(t) do
    if type(v) == "table" then
      clone[k] = M.tbl_deep_clone(v)
    else
      clone[k] = v
    end
  end

  return clone
end

function M.tbl_slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

function M.tbl_concat(a, b)
  local result = {}
  for i, v in ipairs(a) do
    result[i] = v
  end
  for i, v in ipairs(b) do
    result[#a + i] = v
  end

  return result
end

function table.pack(...)
  return { n = select("#", ...), ... }
end

function M.is_blank(s)
  return not (s ~= nil and s ~= vim.NIL and string.match(s, "%S") ~= nil)
end

-- Return: Repository
function M.get_repository()
  local conf = config.get_config()
  local candidates = conf.default_remote
  local repo = {}

  for _, candidate in ipairs(candidates) do
    local job = Job:new {
      command = "git",
      args = { "remote", "get-url", candidate },
    }
    job:sync()

    local url = table.concat(job:result(), "\n")
    local stderr = table.concat(job:stderr_result(), "\n")

    if M.is_blank(stderr) then
      if #vim.split(url, "://") == 2 then
        local hostname, owner, name = string.match(url, '%a+://([^/]+)/(.+)/(.+)')
        name = string.gsub(name, ".git$", "")

        repo.hostname = hostname
        repo.owner = owner
        repo.name = name
      elseif #vim.split(url, "@") == 2 then
        -- TODO: GitLab does currently not support suchs URIs
        local segment = vim.split(url, ":")[2]
        repo.hostname = "github.com" -- TODO: Defaulting to GitHub
        repo.owner = vim.split(segment, "/")[1]
        repo.name = string.gsub(vim.split(segment, "/")[2], ".git$", "")
      end

      repo.full_path = string.format("%s/%s", repo.owner, repo.name)
      return repo
    end
  end
end

function M.split_remote_url()
  local conf = config.get_config()
  local candidates = conf.default_remote
  for _, candidate in ipairs(candidates) do
    local job = Job:new {
      command = "git",
      args = { "remote", "get-url", candidate },
    }
    job:sync()

    local url = table.concat(job:result(), "\n")
    local stderr = table.concat(job:stderr_result(), "\n")

    if M.is_blank(stderr) then
      local hostname, owner, name
      if #vim.split(url, "://") == 2 then
        hostname, owner, name = string.match(url, '%a+://([^/]+)/([^/]+)/(.+)')
        name = string.gsub(name, ".git$", "")
      elseif #vim.split(url, "@") == 2 then
        local segment = vim.split(url, ":")[2]
        owner = vim.split(segment, "/")[1]
        name = string.gsub(vim.split(segment, "/")[2], ".git$", "")
        hostname = ""
        -- TODO: Find hostname
      end

      return hostname, owner, name
    end
  end
end

function M.get_remote_hostname()
  hostname, _, _ = M.split_remote_url()
  return hostname
end

function M.get_remote_name()
  _, owner, name = M.split_remote_url()
  return string.format("%s/%s", owner, name)
end

function M.commit_exists(commit, cb)
  if not Job then
    return
  end
  Job
    :new({
      enable_recording = true,
      command = "git",
      args = { "cat-file", "-t", commit },
      on_exit = vim.schedule_wrap(function(j_self, _, _)
        if "commit" == vim.fn.trim(table.concat(j_self:result(), "\n")) then
          cb(true)
        else
          cb(false)
        end
      end),
    })
    :start()
end

function M.get_file_at_commit(path, commit, cb)
  if not Job then
    return
  end
  local job = Job:new {
    enable_recording = true,
    command = "git",
    args = { "show", string.format("%s:%s", commit, path) },
    on_exit = vim.schedule_wrap(function(j_self, _, _)
      local output = table.concat(j_self:result(), "\n")
      local stderr = table.concat(j_self:stderr_result(), "\n")
      cb(vim.split(output, "\n"), vim.split(stderr, "\n"))
    end),
  }
  job:start()
end

function M.in_pr_repo()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    M.notify("Not in Octo buffer", 2)
    return
  end
  if not buffer:isPullRequest() then
    M.notify("Not in Octo PR buffer", 2)
    return
  end

  local local_repo = M.get_remote_name()
  if buffer.node.baseRepository.nameWithOwner ~= local_repo then
    M.notify(
      string.format("Not in PR repo. Expected %s, got %s", buffer.node.baseRepository.nameWithOwner, local_repo),
      2
    )
    return false
  else
    return true
  end
end

function M.in_pr_branch(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  if not buffer:isPullRequest() then
    --M.notify("Not in Octo PR buffer", 2)
    return false
  end

  local cmd = "git rev-parse --abbrev-ref HEAD"
  local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")
  if local_branch == string.format("%s/%s", buffer.node.headRepoName, buffer.node.headRefName) then
    -- for PRs submitted from master, local_branch will get something like other_repo/master
    local_branch = vim.split(local_branch, "/")[2]
  end

  local local_repo = M.get_remote_name()
  if buffer.node.baseRepository.nameWithOwner == local_repo and buffer.node.headRefName == local_branch then
    return true
  elseif buffer.node.baseRepository.nameWithOwner ~= local_repo then
    --M.notify(string.format("Not in PR repo. Expected %s, got %s", buffer.node.baseRepository.nameWithOwner, local_repo), 2)
    return false
  elseif buffer.node.headRefName ~= local_branch then
    -- TODO: suggest to checkout the branch
    --M.notify(string.format("Not in PR branch. Expected %s, got %s", buffer.node.headRefName, local_branch), 2)
    return false
  else
    return false
  end
end

function M.checkout_pr(headRefName)
  if not Job then
    return
  end
  Job
    :new({
      enable_recording = true,
      command = "git",
      args = { "checkout", headRefName },
      on_exit = vim.schedule_wrap(function(j_self, _, _)
        local stderr = table.concat(j_self:stderr_result(), "\n")
        for _, line in ipairs(vim.fn.split(stderr, "\n")) do
          if line:match "Switched to" or line:match "Already on" then
            M.notify("" .. line, 1)
            return
          end
        end
        M.notify("" .. stderr, 2)
      end),
    })
    :start()
end

function M.get_current_pr()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    M.notify("Not in an active Octo buffer", 2)
    return
  end
  if not buffer:isPullRequest() then
    M.notify("Not in a PR buffer", 2)
    return
  end

  local Rev = require("octo.reviews.rev").Rev
  local PullRequest = require("octo.model.pull-request").PullRequest
  return PullRequest:new {
    bufnr = bufnr,
    repo = buffer.repo,
    number = buffer.number,
    id = buffer.node.id,
    left = Rev:new(buffer.node.baseRefOid),
    right = Rev:new(buffer.node.headRefOid),
    files = buffer.node.files.nodes,
  }
end

function M.get_comment_at_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  return M.get_comment_at_line(bufnr, cursor[1])
end

function M.get_comment_at_line(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  for _, comment in ipairs(buffer.commentsMetadata) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(
      bufnr,
      constants.OCTO_COMMENT_NS,
      comment.extmark,
      { details = true }
    )
    local start_line = mark[1] + 1
    local end_line = mark[3]["end_row"] + 1
    if start_line + 1 <= line and end_line - 2 >= line then
      comment.bufferStartLine = start_line
      comment.bufferEndLine = end_line
      return comment
    end
  end
end

function M.get_body_at_cursor(bufnr)
  local buffer = octo_buffers[bufnr]
  local cursor = vim.api.nvim_win_get_cursor(0)
  local metadata = buffer.bodyMetadata
  local mark = vim.api.nvim_buf_get_extmark_by_id(
    bufnr,
    constants.OCTO_COMMENT_NS,
    metadata.extmark,
    { details = true }
  )
  local start_line = mark[1] + 1
  local end_line = mark[3]["end_row"] + 1
  if start_line + 1 <= cursor[1] and end_line - 2 >= cursor[1] then
    return metadata, start_line, end_line
  end
  return nil
end

function M.get_thread_at_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  return M.get_thread_at_line(bufnr, cursor[1])
end

function M.get_thread_at_line(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local thread_marks = vim.api.nvim_buf_get_extmarks(bufnr, constants.OCTO_THREAD_NS, 0, -1, { details = true })
  for _, mark in ipairs(thread_marks) do
    local thread = buffer.threadsMetadata[tostring(mark[1])]
    if thread then
      local startLine = mark[2] - 1
      local endLine = mark[4].end_row
      if startLine <= line and endLine >= line then
        thread.bufferStartLine = startLine
        thread.bufferEndLine = endLine
        return thread
      end
    end
  end
  return
end

function M.update_reactions_at_cursor(bufnr, reaction_groups, reaction_line)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local buffer = octo_buffers[bufnr]
  local reactions_count = 0
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count + 1
    end
  end

  local comments = buffer.commentsMetadata
  for i, comment in ipairs(comments) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(
      bufnr,
      constants.OCTO_COMMENT_NS,
      comment.extmark,
      { details = true }
    )
    local start_line = mark[1] + 1
    local end_line = mark[3].end_row + 1
    if start_line <= cursor[1] and end_line >= cursor[1] then
      --  cursor located in the body of a comment
      --  update reaction groups
      comments[i].reactionGroups = reaction_groups

      -- update reaction line
      if not comments[i].reactionLine and reactions_count > 0 then
        comments[i].reactionLine = reaction_line
      elseif reactions_count == 0 then
        comments[i].reactionLine = nil
      end

      return
    end
  end

  -- cursor not located at any comment, so updating issue
  --  update reaction groups
  buffer.bodyMetadata.reactionGroups = reaction_groups
  local body_reaction_line = buffer.bodyMetadata.reactionLine
  if not body_reaction_line and reactions_count > 0 then
    buffer.bodyMetadata.reactionLine = reaction_line
  elseif reactions_count == 0 then
    buffer.bodyMetadata.reactionLine = nil
  end
end

function M.format_date(date_string)
  local time_bias = date():getbias() * -1
  local d = date(date_string):addminutes(time_bias)
  local now = date(os.time())
  local diff = date.diff(now, d)
  if diff:spandays() > 0 and diff:spandays() > 30 and now:getyear() ~= d:getyear() then
    return string.format("%s %s %d", d:getyear(), d:fmt "%b", d:getday())
  elseif diff:spandays() > 0 and diff:spandays() > 30 and now:getyear() == d:getyear() then
    return string.format("%s %d", d:fmt "%b", d:getday())
  elseif diff:spandays() > 0 and diff:spandays() <= 30 then
    return tostring(math.floor(diff:spandays())) .. " days ago"
  elseif diff:spanhours() > 0 then
    return tostring(math.floor(diff:spanhours())) .. " hours ago"
  elseif diff:spanminutes() > 0 then
    return tostring(math.floor(diff:spanminutes())) .. " minutes ago"
  elseif diff:spanseconds() > 0 then
    return tostring(math.floor(diff:spanswconds())) .. " seconds ago"
  else
    return string.format("%s %s %d", d:getyear(), d:fmt "%b", d:getday())
  end
end

function M.get_repo_id(repo)
  if repo_id_cache[repo] then
    return repo_id_cache[repo]
  else
    local owner, name = M.split_repo(repo)
    local query = graphql("repository_id_query", owner, name)
    local output = gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      mode = "sync",
    }
    local resp = vim.fn.json_decode(output)
    local id = resp.data.repository.id
    repo_id_cache[repo] = id
    return id
  end
end

function M.get_pages(text)
  local results = {}
  local page_outputs = vim.split(text, "\n")
  for _, page in ipairs(page_outputs) do
    local decoded_page = vim.fn.json_decode(page)
    table.insert(results, decoded_page)
  end
  return results
end

function M.get_flatten_pages(text)
  local results = {}
  local page_outputs = vim.split(text, "\n")
  for _, page in ipairs(page_outputs) do
    local decoded_page = vim.fn.json_decode(page)
    for _, result in ipairs(decoded_page) do
      table.insert(results, result)
    end
  end
  return results
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
  return string.gsub(string, '["\\]', {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
  })
end

function M.get_repo_number_from_varargs(...)
  local repo, number
  local args = table.pack(...)
  if args.n == 0 then
    M.notify("Missing arguments", 1)
    return
  elseif args.n == 1 then
    repo = M.get_remote_name()
    number = tonumber(args[1])
  elseif args.n == 2 then
    repo = args[1]
    number = tonumber(args[2])
  else
    M.notify("Unexpected arguments", 1)
    return
  end
  if not repo then
    M.notify("Cant find repo name", 1)
    return
  end
  if not number then
    M.notify("Missing issue/pr number", 1)
    return
  end
  return repo, number
end

--- Get the URI for a repository
function M.get_repo_uri(_, repo)
  return string.format("octo://%s/repo", repo)
end

function M.get_issue_obj_uri(issue)
  return string.format("octo://%s/issue/%s", issue.repo.full_path, tostring(issue.id))
end

--- Get the URI for an issue
function M.get_issue_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  return string.format("octo://%s/issue/%s", repo, number)
end

--- Get the URI for an pull request
function M.get_pull_request_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  return string.format("octo://%s/pull/%s", repo, number)
end

function M.get_repo(_, repo)
  vim.cmd("edit " .. M.get_repo_uri(_, repo))
end

function M.get_issue(...)
  vim.cmd("edit " .. M.get_issue_uri(...))
end

function M.get_pull_request(...)
  vim.cmd("edit " .. M.get_pull_request_uri(...))
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
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not M.is_blank(stderr) then
        M.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local blob = resp.data.repository.object
        local lines = {}
        if blob and blob ~= vim.NIL and type(blob.text) == "string" then
          lines = vim.split(blob.text, "\n")
        end
        cb(lines)
      end
    end,
  }
end

function M.set_timeout(delay, callback, ...)
  local timer = vim.loop.new_timer()
  local args = { ... }
  vim.loop.timer_start(timer, delay, 0, function()
    vim.loop.timer_stop(timer)
    vim.loop.close(timer)
    callback(unpack(args))
  end)
  return timer
end

function M.getwin4buf(bufnr)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  for _, w in ipairs(wins) do
    if bufnr == vim.api.nvim_win_get_buf(w) then
      return w
    end
  end
  return -1
end

function M.cursor_in_col_range(start_col, end_col)
  local cursor = vim.api.nvim_win_get_cursor(0)
  if start_col and end_col then
    if start_col <= cursor[2] and cursor[2] <= end_col then
      return true
    end
  end
  return false
end

function M.sum_array(arr, start_index)
  local str = {}

  for k, v in ipairs(arr) do
    if k >= start_index then
      strs[k] = v
    end
  end

  return str
end

function M.split_repo(repo)
  local owner, name = string.match(repo, '[^/]+/([^/]+)/(.+)')
  return owner, name
end

function M.reactions_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local cursor = vim.api.nvim_win_get_cursor(0)
  local body_reaction_line = buffer.bodyMetadata.reactionLine
  if body_reaction_line and body_reaction_line == cursor[1] then
    return buffer.node.id
  end

  local comments_metadata = buffer.commentsMetadata
  if comments_metadata then
    for _, c in pairs(comments_metadata) do
      if c.reactionLine and c.reactionLine == cursor[1] then
        return c.id
      end
    end
  end
  return nil
end

function M.extract_pattern_at_cursor(pattern)
  local current_line = vim.fn.getline "."
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
    words[#words + 1] = word
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
  for k = 1, #lines do
    local sourceLine = lines[k]
    widthLeft = width -- all the width is left
    local words = M.pattern_split(sourceLine, "%S+")
    for l = 1, #words do
      local word = words[l]
      -- If the word is longer than an entire line:
      if #word > width then
        -- In case the word is longer than multible lines:
        while #word > width do
          -- Fit as much as possible
          table.insert(line, word:sub(0, widthLeft))
          table.insert(result, table.concat(line, " "))

          -- Take the rest of the word for next round
          word = word:sub(widthLeft + 1)
          widthLeft = width
          line = {}
        end

        -- The rest of the word that could share a line
        line = { word }
        widthLeft = width - (#word + 1)

        -- If we have no space left in the current line
      elseif (#word + 1) > widthLeft then
        table.insert(result, table.concat(line, " "))

        -- start next line
        line = { word }
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
      reactions_count = reactions_count + 1
    end
  end
  return reactions_count
end

function M.get_sorted_comment_lines(bufnr)
  local lines = {}
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, constants.OCTO_COMMENT_NS, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    table.insert(lines, mark[2])
  end
  table.sort(lines)
  return lines
end

function M.is_thread_placed_in_buffer(comment, bufnr)
  local split, path = M.get_split_and_path(bufnr)
  if not split or not path then
    return false
  end
  if split == comment.diffSide and path == comment.path then
    return true
  end
  return false
end

function M.get_split_and_path(bufnr)
  local ok, props = pcall(vim.api.nvim_buf_get_var, bufnr, "octo_diff_props")
  if ok and props then
    return props.split, props.path
  end
end

-- clear buffer undo history
function M.clear_history()
  if true then
    return
  end
  local old_undolevels = vim.o.undolevels
  vim.o.undolevels = -1
  vim.cmd [[exe "normal a \<BS>"]]
  vim.o.undolevels = old_undolevels
end

function M.clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

function M.enum(t)
  for i, v in ipairs(t) do
    t[v] = i
  end
  return t
end

function M.find_named_buffer(name)
  for _, v in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.bufname(v) == name then
      return v
    end
  end
  return nil
end

function M.wipe_named_buffer(name)
  local bn = M.find_named_buffer(name)
  if bn then
    local win_ids = vim.fn.win_findbuf(bn)
    for _, id in ipairs(win_ids) do
      if vim.fn.win_gettype(id) ~= "autocmd" then
        vim.api.nvim_win_close(id, true)
      end
    end

    vim.api.nvim_buf_set_name(bn, "")
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, bn, {})
    end)
  end
end

function M.str_shorten(s, new_length)
  if string.len(s) > new_length - 1 then
    return "…" .. s:sub(string.len(s) - new_length + 1, string.len(s))
  end
  return s
end

---Get a path relative to another path.
---@param path string
---@param relative_to string
---@return string
function M.path_relative(path, relative_to)
  local p, _ = path:gsub("^" .. M.path_to_matching_str(M.path_add_trailing(relative_to)), "")
  return p
end

function M.path_to_matching_str(path)
  return path:gsub("(%-)", "(%%-)"):gsub("(%.)", "(%%.)"):gsub("(%_)", "(%%_)")
end

function M.path_add_trailing(path)
  if path:sub(-1) == path_sep then
    return path
  end

  return path .. path_sep
end

---Get the path to the parent directory of the given path. Returns `nil` if the
---path has no parent.
---@param path string
---@param remove_trailing boolean
---@return string|nil
function M.path_parent(path, remove_trailing)
  path = " " .. M.path_remove_trailing(path)
  local i = path:match("^.+()" .. path_sep)
  if not i then
    return nil
  end
  path = path:sub(2, i)
  if remove_trailing then
    path = M.path_remove_trailing(path)
  end
  return path
end

function M.path_remove_trailing(path)
  local p, _ = path:gsub(path_sep .. "$", "")
  return p
end

---Get the basename of the given path.
---@param path string
---@return string
function M.path_basename(path)
  path = M.path_remove_trailing(path)
  local i = path:match("^.*()" .. path_sep)
  if not i then
    return path
  end
  return path:sub(i + 1, #path)
end

function M.path_extension(path)
  path = M.path_basename(path)
  return path:match ".*%.(.*)"
end

function M.path_join(paths)
  return table.concat(paths, path_sep)
end

-- calculate valid comment ranges
function M.process_patch(patch)
  -- @@ -from,no-of-lines in the file before  +from,no-of-lines in the file after @@
  -- The no-of-lines values may not be immediately obvious.
  -- The 'before' value is the sum of the 3 lead context lines, the number of - lines, and the 3 trailing context lines
  -- The 'after' values is the sum of 3 lead context lines, the number of + lines and the 3 trailing lines.
  -- In some cases there are additional intermediate context lines which are also added to those numbers.
  -- So the total number of lines displayed is commonly neither of the no-of-lines values!

  if not patch then
    return
  end
  local hunks = {}
  local left_ranges = {}
  local right_ranges = {}
  local hunk_strings = vim.split(patch:gsub("^@@", ""), "\n@@")
  for _, hunk in ipairs(hunk_strings) do
    local header = vim.split(hunk, "\n")[1]
    local found, _, left_start, left_length, right_start, right_length = string.find(
      header,
      "^%s*%-(%d+),(%d+)%s+%+(%d+),(%d+)%s*@@"
    )
    if found then
      table.insert(hunks, hunk)
      table.insert(left_ranges, { tonumber(left_start), math.max(left_start + left_length - 1, 0) })
      table.insert(right_ranges, { tonumber(right_start), math.max(right_start + right_length - 1, 0) })
    else
      found, _, left_start, left_length, right_start = string.find(header, "^%s*%-(%d+),(%d+)%s+%+(%d+)%s*@@")
      if found then
        right_length = right_start + 1
        table.insert(hunks, hunk)
        table.insert(left_ranges, { tonumber(left_start), math.max(left_start + left_length - 1, 0) })
        table.insert(right_ranges, { tonumber(right_start), math.max(right_start + right_length - 1, 0) })
      end
    end
  end
  return hunks, left_ranges, right_ranges
end

-- calculate GutHub diffstat histogram bar
function M.diffstat(stats)
  -- round up to closest multiple of 5
  local total = stats.additions + stats.deletions
  if total == 0 then
    return {
      total = 0,
      additions = 0,
      deletions = 0,
      neutral = 5,
    }
  end
  local mod = total % 5
  local round = total - mod
  if mod > 0 then
    round = round + 5
  end
  -- calculate insertion to deletion ratio
  local unit = round / 5
  local additions = math.floor((0.5 + stats.additions) / unit)
  local deletions = math.floor((0.5 + stats.deletions) / unit)
  local neutral = 5 - additions - deletions
  return {
    total = total,
    additions = additions,
    deletions = deletions,
    neutral = neutral,
  }
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
  local status, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line + 1, true)
  if status and lines then
    local text = vim.fn.join(lines, "\n")
    return start_line, end_line, text
  end
end

function M.fork_repo()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]

  if not buffer or not buffer:isRepo() then
    return
  end
  M.notify(string.format("Cloning %s. It can take a few minutes", buffer.repo), 1)
  M.notify(vim.fn.system('echo "n" | gh repo fork ' .. buffer.repo .. " 2>&1 | cat "), 1)
end

function M.notify(msg, kind)
  vim.notify(msg, kind, { title = "Octo.nvim" })
end

function M.get_pull_request_for_current_branch(cb)
  gh.run {
    args = { "pr", "status", "--json", "id,number,headRepositoryOwner,headRepository" },
    cb = function(output)
      local pr = vim.fn.json_decode(output)
      if pr.currentBranch and pr.currentBranch.number then
        local number = pr.currentBranch.number
        local id = pr.currentBranch.id
        local owner = pr.currentBranch.headRepositoryOwner.login
        local name = pr.currentBranch.headRepository.name
        local query = graphql("pull_request_query", owner, name, number)
        gh.run {
          args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
          cb = function(output, stderr)
            if stderr and not M.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              local resp = M.aggregate_pages(
                output,
                string.format("data.repository.%s.timelineItems.nodes", "pullRequest")
              )
              local obj = resp.data.repository.pullRequest
              local Rev = require("octo.reviews.rev").Rev
              local PullRequest = require("octo.model.pull-request").PullRequest
              local pull_request = PullRequest:new {
                repo = owner .. "/" .. name,
                number = number,
                id = id,
                left = Rev:new(obj.baseRefOid),
                right = Rev:new(obj.headRefOid),
                files = obj.files.nodes,
              }
              cb(pull_request)
            end
          end,
        }
      end
    end,
  }
end

--- Creates autocommands to close a preview window when events happen.
---
---@param events table list of events
---@param winnr number window id of preview window
---@param bufnrs table list of buffers where the preview window will remain visible
---@see |autocmd-events|
function M.close_preview_autocmd(events, winnr, bufnrs)
  local augroup = "preview_window_" .. winnr

  -- close the preview window when entered a buffer that is not
  -- the floating window buffer or the buffer that spawned it
  vim.cmd(string.format(
    [[
    augroup %s
      autocmd!
      autocmd BufEnter * lua vim.lsp.util._close_preview_window(%d, {%s})
    augroup end
  ]],
    augroup,
    winnr,
    table.concat(bufnrs, ",")
  ))

  if #events > 0 then
    vim.cmd(string.format(
      [[
      augroup %s
        autocmd %s <buffer> lua vim.lsp.util._close_preview_window(%d)
      augroup end
    ]],
      augroup,
      table.concat(events, ","),
      winnr
    ))
  end
end

function M.get_user_id(login)
  local query = graphql("user_query", login)
  local output = gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if output then
    local resp = vim.fn.json_decode(output)
    if resp.data.user and resp.data.user ~= vim.NIL then
      return resp.data.user.id
    end
  end
end

function M.get_label_id(label)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    M.notify("Not in Octo buffer", 2)
    return
  end

  local owner, name = M.split_repo(buffer.repo)
  local query = graphql("repo_labels_query", owner, name)
  local output = gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if output then
    local resp = vim.fn.json_decode(output)
    if resp.data.repository.labels.nodes and resp.data.repository.labels.nodes ~= vim.NIL then
      for _, l in ipairs(resp.data.repository.labels.nodes) do
        if l.name == label then
          return l.id
        end
      end
    end
  end
end

return M
