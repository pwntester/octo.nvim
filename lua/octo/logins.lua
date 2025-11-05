---Helpers and Aliases for various logins

local utils = require "octo.utils"
local config = require "octo.config"

local M = {}

local copilot_logins = { "copilot-swe-agent", "copilot-pull-request-reviewer" }

---Formats author login for display
---@param author? {login: string}
---@return { name?: string, login?: string, isViewer?: boolean }
M.format_author = function(author)
  if author == nil or utils.is_blank(author) then
    return { login = "ghost" }
  end

  if vim.tbl_contains(copilot_logins, author.login) then
    return { login = "Copilot" }
  end

  return author
end

---Gets user icon based on login
---@param login string
---@return string icon
M.get_user_icon = function(login)
  local conf = config.values
  if login == "ghost" then
    return conf.ghost_icon
  elseif login == "Copilot" then
    return conf.copilot_icon
  else
    return conf.user_icon
  end
end

return M
