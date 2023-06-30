local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

return function(opts)
  opts = opts or {}

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
          local output = gh.run {
            args = { "api", "graphql", "-f", string.format("query=%s", graphql("search_query", _prompt)) },
            mode = "sync",
          }

          if output then
            local resp = vim.fn.json_decode(output)
            local max_id_length = 1
            for _, issue in ipairs(resp.data.search.nodes) do
              local s = tostring(issue.number)
              if #s > max_id_length then
                max_id_length = #s
              end
            end

            for _, issue in ipairs(resp.data.search.nodes) do
              vim.schedule(function()
                local entry = entry_maker.gen_from_issue(issue)
                if entry ~= nil then
                  local owner, name = utils.split_repo(entry.repo)
                  local number =
                    fzf.utils.ansi_from_hl("Comment", picker_utils.pad_string(entry.obj.number, max_id_length))
                  local string_entry = string.format("%s %s %s %s %s", entry.kind, owner, name, number, entry.obj.title)
                  fzf_cb(string_entry, function()
                    coroutine.resume(co)
                  end)
                end
              end)
              coroutine.yield()
            end
          end
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
    fzf_opts = {
      ["--info"] = "default",
      ["--delimiter"] = "' '",
      ["--with-nth"] = "4..",
    },
    actions = fzf_actions.common_open_actions(formatted_issues),
  })
end
