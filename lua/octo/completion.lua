local M = {}
local vim = vim

function M.octo_command_complete(argLead, cmdLine)
  -- ArgLead		the leading portion of the argument currently being completed on
  -- CmdLine		the entire command line
  -- CursorPos	the cursor position in it (byte index)
  local octo_commands = require "octo.commands"
  local command_keys = vim.tbl_keys(octo_commands.commands)
  local parts = vim.split(vim.trim(cmdLine), " ")

  local get_options = function(options)
    local valid_options = {}
    for _, option in pairs(options) do
      if string.sub(option, 1, #argLead) == argLead then
        table.insert(valid_options, option)
      end
    end
    return valid_options
  end

  if #parts == 1 then
    return command_keys
  elseif #parts == 2 and not vim.tbl_contains(command_keys, parts[2]) then
    return get_options(command_keys)
  elseif #parts == 2 and vim.tbl_contains(command_keys, parts[2]) or #parts == 3 then
    local obj = octo_commands.commands[parts[2]]
    if type(obj) == "table" then
      return get_options(vim.tbl_keys(obj))
    end
  end
end

function M.setup()
  function _G.octo_omnifunc(findstart, base)
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
end

return M
