local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

local function map(tbl, f)
  local t = {}
  for k,v in pairs(tbl) do
    t[k] = f(v)
  end
  return t
end

local function reduce(tbl, start, f)
  local acc = start

  for k, v in pairs(tbl) do
    f(acc, v)
  end

  return acc
end

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
      local fields = map(card.fieldValues.nodes, function (fieldValue)
        if fieldValue.field == nil then
          return fieldValue
        end

        return {
          k = fieldValue.field.name,
          v = {
            name = fieldValue.name,
            optionId = fieldValue.optionId
          }
        }
      end)

      local reduced = reduce(fields, {}, function (acc, curr)
        if curr.k ~= nil then
          acc[curr.k] = curr.v
        end
      end)

      table.insert(titles, string.format("%s %s %s (%s)", card.project.id, card.id, reduced.Status.name, card.project.title))
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
