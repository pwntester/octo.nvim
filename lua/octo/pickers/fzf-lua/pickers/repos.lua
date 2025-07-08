---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

return function(opts)
  opts = opts or {}

  local formatted_repos = {} ---@type table<string, table> entry.ordinal -> entry

  local function get_contents(fzf_cb)
    gh.api.graphql {
      query = queries.repos,
      f = { login = opts.login },
      paginate = true,
      jq = ".data.repositoryOwner.repositories.nodes",
      opts = {
        cb = function()
          fzf_cb()
        end,
        stream_cb = gh.create_callback {
          failure = function(stderr)
            utils.error(stderr)
            fzf_cb()
          end,
          success = function(output)
            local repos = utils.get_flatten_pages(output)

            if #repos == 0 then
              utils.error(string.format("There are no matching repositories for %s.", opts.login))
              return
            end

            for _, repo in ipairs(repos) do
              local entry, entry_str = entry_maker.gen_from_repo(repo)

              if entry ~= nil and entry_str ~= nil then
                formatted_repos[fzf.utils.strip_ansi_coloring(entry_str)] = entry
                fzf_cb(entry_str)
              end
            end
          end,
        },
      },
    }
  end

  fzf.fzf_exec(get_contents, {
    previewer = previewers.repo(formatted_repos),
    prompt = picker_utils.get_prompt(opts.prompt_title),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
      -- ["--delimiter"] = "' '",
      -- ["--with-nth"] = "1..5",
    },
    actions = fzf_actions.common_open_actions(formatted_repos),
  })
end
