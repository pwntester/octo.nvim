---@diagnostic disable
local config = require "octo.config"
local utils = require "octo.utils"

---@class octo.PickerModule The picker module provides various pickers for different GitHub entities.
---@field actions function The actions that can be performed in pickers
---@field assigned_labels function Get labels assigned to an issue or PR
---@field assignees function Get assignees for an issue or PR
---@field changed_files function Get changed files in a PR
---@field commits function Get commits
---@field discussions function Get discussions
---@field gists function Get gists
---@field issue_templates function Get issue templates
---@field issues function Get issues
---@field labels function Get labels for issue or PR
---@field milestones function Get milestones
---@field notifications function Get notfications
---@field pending_threads function Get pending review threads
---@field project_cards_v2 function Get project cards
---@field project_columns_v2 function Get project columns
---@field prs function Get pull requests
---@field repos function Get repositories
---@field review_commits function Get review commits
---@field search function Get search results
---@field users function Get users
---@field workflow_runs function Get workflow runs

---@type octo.PickerModule
local M = {}

function M.setup()
  local provider_name = config.values.picker
  if utils.is_blank(provider_name) then
    provider_name = "telescope"
  end
  setmetatable(M, {
    __index = function(_, key)
      return function()
        utils.error(
          utils.title_case(provider_name)
            .. " doesn't support the "
            .. key
            .. " picker. Please create issue or submit a PR to add it."
        )
      end
    end,
  })
  local ok, provider = pcall(require, string.format("octo.pickers.%s.provider", provider_name))
  if ok then
    for k, v in pairs(provider.picker) do
      M[k] = v
    end
  else
    utils.error("Error loading picker provider " .. provider_name)
  end
end

return M
