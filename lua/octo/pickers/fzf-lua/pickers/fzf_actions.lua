local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local log = require "octo.pickers.fzf-lua.log"
local M = {}

M.common_buffer_actions = function(formatted_items)
  return {
    ["default"] = function(selected)
      log.info(selected)
      if #selected > 1 then
        local selected_items = vim.tbl_map(function(i)
          log.info('adding to quickfix list', formatted_items[i])
          return formatted_items[i]
        end, selected)
        vim.fn.setqflist({}, " ", {
          title = "Octo",
          lines = vim.tbl_map(function(i)
            log.info('adding to quickfix list', formatted_items[i])
            return formatted_items[i].filename .. "#0#" .. formatted_items[i].ordinal
          end, selected),
          efm = "%f#%l#%m"
        })
        vim.cmd "copen"
      else
        picker_utils.open("default", formatted_items[selected[1]])
      end
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
