local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

return function(templates, cb)
  local opts = {
    preview_title = "",
    prompt_title = "Issue templates",
    results_title = "",
  }

  local titles = {}
  local formatted_templates = {}

  for _, template in ipairs(templates) do
    local entry = entry_maker.gen_from_issue_templates(template)
    if entry ~= nil then
      table.insert(titles, entry.friendly_title)
      formatted_templates[entry.ordinal] = entry
    end
  end

  fzf.fzf_exec(titles, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    previewer = previewers.issue_template(formatted_templates),
    actions = {
      ["default"] = function(selected)
        local entry = formatted_templates[selected[1]]
        cb(entry.template)
      end,
    },
  })
end
