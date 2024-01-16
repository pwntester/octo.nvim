local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local cards = buffer.node.projectItems
  if not cards or #cards.nodes == 0 then
    utils.error "Can't find any project v2 cards"
    return
  end

  if #cards.nodes == 1 then
    callback(cards.nodes[1].project.id, cards.nodes[1].id)
  else
    local titles = {}

    for _, card in ipairs(cards.nodes) do
      local status = nil

      for _, node in ipairs(card.fieldValues.nodes) do
        if node.field ~= nil and node.field.name == "Status" then
          status = node.field.name
          break
        end
      end

      if status == nil then
        status = "<No status>"
      end

      table.insert(titles, string.format("%s %s %s (%s)", card.project.id, card.id, status, card.project.title))
    end

    fzf.fzf_exec(
      titles,
      vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
        fzf_opts = {
          ["--no-multi"] = "", -- TODO this can support multi, maybe.
          ["--delimiter"] = "' '",
          ["--with-nth"] = "3..",
        },
        actions = {
          ["default"] = function(selected)
            local project_id, item_id, _ = unpack(vim.split(selected[1], " "))
            callback(project_id, item_id)
          end,
        },
      })
    )
  end
end
