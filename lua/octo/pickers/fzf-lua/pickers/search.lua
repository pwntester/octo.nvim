local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local log = require "octo.pickers.fzf-lua.log"

local handle_entry = function(fzf_cb, issue, max_id_length, co)
  local entry_string = entry_maker.entry_string_from_issue_or_pr(issue, function (tbl)
    local raw_number = picker_utils.pad_string(tbl.number, max_id_length)
    return fzf.utils.ansi_from_hl("Comment", raw_number)
  end)
  if entry_string ~= nil then
    log.info('entry_string', entry_string)
    fzf_cb(entry_string, function()
      coroutine.resume(co)
    end)
  end
end

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

          if not output then
            return {}
          end

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
              handle_entry(fzf_cb, issue, max_id_length, co)
            end)
            coroutine.yield()
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
    query_delay = 250,
    fzf_opts = {
      ["--info"] = "default",
      ["--multi"] = true,
      ["--delimiter"] = " ",
      ["--with-nth"] = "4..",
    },
    actions = fzf_actions.common_open_actions_v2(),
    _fmt = {
      from = function(entry)
        local split = vim.split(entry, " ")
        return split[1] .. ":1:1:" .. table.concat(split, " ", 2)
      end,
    },
    parse_entry = function(entry)
      log.info('entry here', entry)
      local match = string.gmatch(entry, "[^%s]+")
      local _ = match()
      local _ = match()
      local repo = match()
      local owner, name = utils.split_repo(repo)
      local number = match()
      return {
        kind = opts.kind,
        number = number,
        owner = owner,
        name = name,
      }
    end,
  })
end
