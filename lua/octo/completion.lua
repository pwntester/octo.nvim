local gh = require("octo.gh")
local format = string.format
local api = vim.api
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

local function get_url(url, params)
  url = url .. "?foo=bar"
  for k, v in pairs(params) do
    url = format("%s&%s=%s", url, k, v)
  end
  return url
end

local function get_repo_issues(repo, params)
  params = params or {}
  local query_params = {
    state = params.state or "open",
    per_page = params.per_page or 50,
    filter = params.filter,
    labels = params.labels,
    since = params.since
  }

  local query = get_url(format("repos/%s/issues", repo), query_params)
  local body =
    gh.run(
    {
      args = {"api", query},
      mode = "sync"
    }
  )

  local issues = json.parse(body)

  -- TODO: filter out pull_requests (NOT WORKING)
  vim.tbl_filter(
    function(e)
      return e.pull_request == nil
    end,
    issues
  )

  return issues
end

function M.issue_complete(findstart, base)
  -- the complete-functions
  if findstart == 1 then
    -- findstart
    local line = api.nvim_get_current_line()
    local pos = vim.fn.col(".")
    local i, j = 0, 0
    while true do
      i, j = string.find(line, "#(%d*)", i + 1)
      if i == nil then
        i, j = 0, 0
        i, j = string.find(line, "@(%w*)", i + 1)
        if i == nil then
          break
        end
      end
      if pos > i and pos <= j + 1 then
        -- I think subtracting 1 is necessary to include the first character
        -- since lua is 1 indexed
        return i - 1
      end
    end
    return -2
  elseif findstart == 0 then
    local repo = api.nvim_buf_get_var(0, "repo")
    local issues = get_repo_issues(repo)
    local entries = {}
    if vim.startswith(base, "@") then
      local users = api.nvim_buf_get_var(0, "taggable_users") or {}
      for _, user in pairs(users) do table.insert(entries, {word = format("@%s", user), abbr = user}) end
    else if vim.startswith(base, "#") then
        for _, i in ipairs(issues) do
          if vim.startswith(tostring(i.number), base) then
            table.insert(
              entries,
              {
                word = tostring(i.number),
                abbr = format("#%d", i.number),
                menu = i.title
              }
              )
          end
        end
      end
    end
    return entries
  end
end
return M
