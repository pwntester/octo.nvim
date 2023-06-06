local actions = require "octo.pickers.fzf-lua.pickers.actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

return function(opts)
  opts = opts or {}
  if not opts.login then
    if vim.g.octo_viewer then
      opts.login = vim.g.octo_viewer
    else
      opts.login = require("octo.gh").get_user_name()
    end
  end

  local formatted_repos = {}

  local get_contents = function(fzf_cb)
    local query = graphql("repos_query", opts.login)
    gh.run {
      args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
      stream_cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
          fzf_cb()
        elseif output then
          local resp = utils.aggregate_pages(output, "data.repositoryOwner.repositories.nodes")
          local repos = resp.data.repositoryOwner.repositories.nodes
          if #repos == 0 then
            utils.error(string.format("There are no matching repositories for %s.", opts.login))
            return
          end
          local max_nameWithOwner = -1
          local max_forkCount = -1
          local max_stargazerCount = -1

          for _, repo in ipairs(repos) do
            max_nameWithOwner = math.max(max_nameWithOwner, #repo.nameWithOwner)
            max_forkCount = math.max(max_forkCount, #tostring(repo.forkCount))
            max_stargazerCount = math.max(max_stargazerCount, #tostring(repo.stargazerCount))
          end

          for _, repo in ipairs(repos) do
            -- TODO this should be handled however.
            local entry, entry_str = entry_maker.gen_from_repo(max_nameWithOwner, max_forkCount, max_stargazerCount, repo)

            if entry ~= nil and entry_str ~= nil then
              formatted_repos[fzf.utils.strip_ansi_coloring(entry_str)] = entry
              fzf_cb(entry_str)
              -- local name = fzf.utils.ansi_from_hl("Directory", entry.value)
              -- local description = fzf.utils.ansi_from_hl("Comment", entry.repo.description)
              -- fzf_cb(name .. " " .. description)
            end
          end
        end
      end,
      cb = function()
        fzf_cb()
      end,
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
    actions = actions.common_open_actions(formatted_repos),
  })
end
