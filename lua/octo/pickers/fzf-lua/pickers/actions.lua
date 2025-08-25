---@diagnostic disable
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(flattened_actions)
  local action_cmds = {}
  local formatted_actions = {}

  local width = 13 -- hard code?

  for _, action in ipairs(flattened_actions) do
    local entry = entry_maker.gen_from_octo_actions(action)
    if not entry or not entry.ordinal then
      utils.error("Failed to process: entry is nil or missing ordinal for action: " .. vim.inspect(action))
      return
    end

    local icon_with_hl = utils.get_icon(entry)
    local icon_str = fzf.utils.ansi_from_hl(icon_with_hl[2], icon_with_hl[1])

    width = math.max(width, #action.object)

    str_split_ordinal = vim.split(entry.ordinal, " ")
    str_cmd_action = fzf.utils.ansi_from_hl("OctoStateOpen", str_split_ordinal[1])

    local entry_string = str_cmd_action .. (" "):rep(width - #str_split_ordinal[1]) .. str_split_ordinal[2]

    entry.ordinal = fzf.utils.strip_ansi_coloring(entry_string)
    formatted_actions[entry.ordinal] = entry

    table.insert(action_cmds, entry_string)
  end

  table.sort(action_cmds)

  fzf.fzf_exec(action_cmds, {
    -- prompt = picker_utils.get_prompt "Actions",
    prompt = "  ",
    fzf_opts = {
      ["--no-multi"] = "",
    },
    actions = {
      ["default"] = function(selected)
        local entry = formatted_actions[selected[1]]
        entry.action.fun()
      end,
    },
  })
end
