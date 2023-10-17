local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local cards = buffer.node.projectCards
  if not cards or #cards.nodes == 0 then
    utils.error "Can't find any project cards"
    return
  end

  if #cards.nodes == 1 then
    callback(cards.nodes[1].id)
  else
    local formatted_cards = {}
    local titles = {}

    for _, card in ipairs(cards.nodes) do
      local entry = entry_maker.gen_from_project_card(card)

      if entry ~= nil then
        formatted_cards[entry.ordinal] = entry
        table.insert(titles, entry.ordinal)
      end
    end

    fzf.fzf_exec(
      titles,
      vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
        fzf_opts = {
          ["--no-multi"] = "", -- TODO this can support multi, maybe.
          ["--delimiter"] = "' '",
          ["--with-nth"] = "2..",
        },
        actions = {
          ["default"] = function(selected)
            local entry = formatted_cards[selected[1]]
            callback(entry.card.id)
          end,
        },
      })
    )
  end
end
