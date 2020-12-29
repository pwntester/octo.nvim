local format = string.format
local api = vim.api

local M = {}

function M.issue_complete(findstart, base)
  -- :help complete-functions
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
    local entries = {}
    if vim.startswith(base, "@") then
      local users = api.nvim_buf_get_var(0, "taggable_users") or {}
      for _, user in pairs(users) do
        table.insert(entries, {word = format("@%s", user), abbr = user})
      end
    else
      if vim.startswith(base, "#") then
        local issues = api.nvim_buf_get_var(0, "issues") or {}
        for _, i in ipairs(issues) do
          if vim.startswith("#" .. tostring(i.number), base) then
            table.insert(
              entries,
              {
                abbr = tostring(i.number),
                word = format("#%d", i.number),
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
