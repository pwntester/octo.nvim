-- TODO not working yet.
local picker_utils = require 'octo.pickers.fzf-lua.pickers.utils'
local M = {}

M.common_issue_pr = function (formatted_items)
  return {
    ['default'] = function (selected)
      local entry = formatted_items[selected[1]]
      picker_utils.open('default', entry)
    end,
    ['ctrl-v'] = function (selected)
      local entry = formatted_items[selected[1]]
      picker_utils.open('vertical', entry)
    end,
    ['ctrl-s'] = function (selected)
      local entry = formatted_items[selected[1]]
      picker_utils.open('horizontal', entry)
    end,
    ['ctrl-t'] = function (selected)
      local entry = formatted_items[selected[1]]
      picker_utils.open('tab', entry)
    end,
    ['ctrl-b'] = function (selected)
      picker_utils.open_in_browser(formatted_items[selected[1]])
    end,
    ['ctrl-y'] = function (selected)
      picker_utils.copy_url(formatted_items[selected[1]])
    end
  }
end

return M
