local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local M = {}

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

M.common_open_actions = function(formatted_items)
  return vim.tbl_extend("force", M.common_buffer_actions(formatted_items), {
    ["ctrl-b"] = function(selected)
      picker_utils.open_in_browser(formatted_items[selected[1]])
    end,
    ["ctrl-y"] = function(selected)
      picker_utils.copy_url(formatted_items[selected[1]])
    end,
  })
end

return M
