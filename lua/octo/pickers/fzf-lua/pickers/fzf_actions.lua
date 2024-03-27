local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local log = require "octo.pickers.fzf-lua.log"
local navigation = require "octo.navigation"
local fzf_actions = require "fzf-lua.actions"
local M = {}

M.common_buffer_actions = function(formatted_items)
  return {
    ["default"] = function(selected, opts)
      if #selected > 1 then
        vim.fn.setqflist({}, " ", {
          title = "Octo",
          lines = vim.tbl_map(function(i)
            log.info("adding to quickfix list", formatted_items[i])
            return formatted_items[i].filename .. "#0#" .. formatted_items[i].ordinal
          end, selected),
          efm = "%f#%l#%m",
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

M.common_buffer_actions_v2 = function()
  local cfg = octo_config.values
  local default = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_or_send_to_qf.lhs)
  local open_splits = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_horizontal_split.lhs)
  local open_vsplits = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_vertical_split.lhs)
  local open_tab = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_tab.lhs)
  local send_to_qf = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.send_to_qf.lhs)
  local send_to_ll = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.send_to_ll.lhs)

  return {
    [default] = function(selected, opts)
      fzf_actions.file_edit_or_qf(selected, opts)
    end,
    [open_splits] = function(selected, opts)
      fzf_actions.file_split(selected, opts)
    end,
    [open_vsplits] = function(selected, opts)
      fzf_actions.file_vsplit(selected, opts)
    end,
    [open_tab] = function(selected, opts)
      fzf_actions.file_tabedit(selected, opts)
    end,
    [send_to_qf]   = fzf_actions.file_sel_to_qf,
    [send_to_ll]   = fzf_actions.file_sel_to_ll,
  }
end

M.common_open_actions_v2 = function()
  local cfg = octo_config.values
  return vim.tbl_extend("force", M.common_buffer_actions_v2(), {
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_in_browser.lhs)] = function(selected, opts)
      for _, s in ipairs(selected) do
        local split = vim.split(s, " ")
        local filename_split = vim.split(split[1], "/")
        navigation.open_in_browser(opts.kind, filename_split[3] .. "/" .. filename_split[4], split[-1])
      end
    end,
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = function(selected, opts)
      -- Only copy the first one. Multiselect in this case makes no sense.
      local split = vim.split(selected[1], " ")
      picker_utils.copy_url_raw(split[2])
    end,
  })
end

return M
