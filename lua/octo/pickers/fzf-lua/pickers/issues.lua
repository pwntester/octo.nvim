---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

return function(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = { "OPEN" }
  end

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local owner, name = utils.split_repo(repo)

  local window_title = utils.pop_key(opts, "window_title") or "Issues"
  local prompt_title = utils.pop_key(opts, "prompt_title")

  local formatted_issues = {} ---@type table<string, table> entry.ordinal -> entry

  local function get_contents(fzf_cb)
    gh.api.graphql {
      query = queries.issues,
      F = {
        owner = owner,
        name = name,
        filter_by = opts,
        order_by = octo_config.values.issues.order_by,
      },
      paginate = true,
      jq = ".",
      opts = {
        stream_cb = function(data, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif data then
            local resp = utils.aggregate_pages(data, "data.repository.issues.nodes")
            local issues = resp.data.repository.issues.nodes

            for _, issue in ipairs(issues) do
              local entry = entry_maker.gen_from_issue(issue)

              if entry ~= nil then
                formatted_issues[entry.ordinal] = entry
                local prefix = fzf.utils.ansi_from_hl("Comment", entry.value)
                fzf_cb(prefix .. " " .. entry.obj.title)
              end
            end
          end
        end,
        cb = function()
          fzf_cb()
        end,
      },
    }
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(prompt_title),
    previewer = previewers.issue(formatted_issues),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--header"] = opts.results_title,
      ["--info"] = "default",
    },
    winopts = {
      title = window_title,
      title_pos = "center",
    },
    actions = fzf_actions.common_open_actions(formatted_issues),
  })
end
