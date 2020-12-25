local api = vim.api

local M = {}

local function is_cursor_in_pattern(pattern)
  local pos = vim.fn.col(".")
  local line = api.nvim_get_current_line()
  local i, j = 0
  while true do
    local res = {string.find(line, pattern, i + 1)}
    i = table.remove(res, 1)
    j = table.remove(res, 1)
    if i == nil then
      break
    end
    if pos > i and pos <= j + 1 then
      return res
    end
  end
  return nil
end

function M.go_to_issue()
  local res = is_cursor_in_pattern("%s#(%d*)")
  if res and #res == 1 then
    local repo = api.nvim_buf_get_var(0, "repo")
    local number = res[1]
    get_issue(repo, number)
    return
  else
    res = is_cursor_in_pattern("https://github.com/([^/]+)/([^/]+)/([^/]+)/(%d+).*")
    if res and #res == 4 then
      local repo = string.format("%s/%s", res[1], res[2])
      local number = res[4]
      get_issue(repo, number)
      return
    end
  end
end

return M
