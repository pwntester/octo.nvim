local config = require "octo.config"
local utils = require "octo.utils"

local provider_name = config.get_config().picker


local ok, provider = pcall(require, string.format("octo.pickers.%s.provider", provider_name))
print(ok)
print(provider)
if ok then
  local picker = provider.picker
  return picker
else
  utils.notify("Error loading " .. provider_name, 2)
end
