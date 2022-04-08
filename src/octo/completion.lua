function _G.octo_command_complete(argLead, cmdLine)
  local command_keys = vim.tbl_keys(require("octo.commands").commands)
  local parts = vim.split(cmdLine, " ")

  local get_options = function(options)
    local valid_options = {}
    for _, option in pairs(options) do
      if string.sub(option, 1, #argLead) == argLead then
        table.insert(valid_options, option)
      end
    end
    return valid_options
  end

  if #parts == 2 then
    return get_options(command_keys)
  elseif #parts == 3 then
    local o = require("octo.commands").commands[parts[2]]
    if not o then
      return
    end
    return get_options(vim.tbl_keys(o))
  end
end

function _G.octo_omnifunc(findstart, base)
  local octo = require "octo"
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  -- :help complete-functions
  if findstart == 1 then
    -- findstart
    local line = vim.api.nvim_get_current_line()
    local pos = vim.fn.col "."

    local start, finish = 0, 0
    while true do
      start, finish = string.find(line, "#(%d*)", start + 1)
      if start and pos > start and pos <= finish + 1 then
        return start - 1
      elseif not start then
        break
      end
    end

    start, finish = 0, 0
    while true do
      start, finish = string.find(line, "@(%w*)", start + 1)
      if start and pos > start and pos <= finish + 1 then
        return start - 1
      elseif not start then
        break
      end
    end

    return -2
  elseif findstart == 0 then
    local entries = {}
    if vim.startswith(base, "@") then
      local users = buffer.taggable_users or {}
      for _, user in pairs(users) do
        table.insert(entries, { word = string.format("@%s", user), abbr = user })
      end
    else
      if vim.startswith(base, "#") then
        local issues = octo_repo_issues[buffer.repo] or {}
        for _, i in ipairs(issues) do
          if vim.startswith("#" .. tostring(i.number), base) then
            table.insert(entries, {
              abbr = tostring(i.number),
              word = string.format("#%d", i.number),
              menu = i.title,
            })
          end
        end
      end
    end
    return entries
  end
end
