local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

local handle_entry = function(fzf_cb, issue, max_id_length, formatted_issues, co)
  local entry = entry_maker.gen_from_issue(issue)
  if entry ~= nil then
    local owner, name = utils.split_repo(entry.repo)
    local raw_number = picker_utils.pad_string(entry.obj.number, max_id_length)
    local number = fzf.utils.ansi_from_hl("Comment", raw_number)
    local ordinal_entry = string.format("%s %s %s %s %s", entry.kind, owner, name, raw_number, entry.obj.title)
    local string_entry = string.format("%s %s %s %s %s", entry.kind, owner, name, number, entry.obj.title)
    formatted_issues[ordinal_entry] = entry
    fzf_cb(string_entry, function()
      coroutine.resume(co)
    end)
  end
end

return function(opts)
  opts = opts or {}

  local formatted_items = {}

  local contents = function(query)
    return function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()

        if not opts.prompt and utils.is_blank(query) then
          return {}
        end

        if type(opts.prompt) == "string" then
          opts.prompt = { opts.prompt }
        end

        for _, val in ipairs(opts.prompt) do
          local _prompt = query
          if val then
            _prompt = string.format("%s %s", val, _prompt)
          end
          local backend = require "octo.backend"
          local func = backend.get_funcs()["fzf_lua_search"]
          func(co, _prompt, fzf_cb)
        end

        fzf_cb()
      end)()
    end
  end

  -- TODO this is still not as fast as I would like.
  fzf.fzf_live(contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    func_async_callback = false,
    previewer = previewers.search(),
    query_delay = 500,
    fzf_opts = {
      ["--info"] = "default",
      ["--delimiter"] = " ",
      ["--with-nth"] = "4..",
    },
    actions = fzf_actions.common_open_actions(formatted_items),
  })
end
