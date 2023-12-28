local config = require "octo.config"
local utils = require "octo.utils"

local M = {}

function M.setup()
  local provider_name = config.values.picker
  if utils.is_blank(provider_name) then
    provider_name = "telescope"
  end
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
