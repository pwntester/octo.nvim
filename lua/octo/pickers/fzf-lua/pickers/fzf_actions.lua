local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local M = {}

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
M.common_buffer_actions = function(formatted_items)
  return {
    ["default"] = function(selected)
      picker_utils.open("default", formatted_items[selected[1]])
    end,
    ["ctrl-v"] = function(selected)
      picker_utils.open("vertical", formatted_items[selected[1]])
    end,
    ["ctrl-s"] = function(selected)
      picker_utils.open("horizontal", formatted_items[selected[1]])
    end,
    ["ctrl-t"] = function(selected)
      picker_utils.open("tab", formatted_items[selected[1]])
    end,
  }
end

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
M.common_open_actions = function(formatted_items)
  local cfg = octo_config.values
  return vim.tbl_extend("force", M.common_buffer_actions(formatted_items), {
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_in_browser.lhs)] = function(selected)
      picker_utils.open_in_browser(formatted_items[selected[1]])
    end,
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = function(selected)
      picker_utils.copy_url(formatted_items[selected[1]])
    end,
  })
end

return M
