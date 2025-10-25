---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local graphql = require "octo.gh.graphql"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

local function checkout_pull_request(entry)
  utils.checkout_pr(entry.obj.number)
end

local function not_implemented()
  utils.error "Not implemented yet"
end

return function(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = { "OPEN" }
  end

  if opts.cb ~= nil then
    not_implemented()
    return
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
  local cfg = octo_config.values

  local window_title = utils.pop_key(opts, "window_title") or "Pull Requests"
  local prompt_title = utils.pop_key(opts, "prompt_title")

  local formatted_pulls = {} ---@type table<string, table> entry.ordinal -> entry

  local function get_contents(fzf_cb)
    gh.api.graphql {
      query = queries.pull_requests,
      F = {
        owner = owner,
        name = name,
        base_ref_name = opts.BaseRefName,
        head_ref_name = opts.HeadRefName,
        labels = opts.labels,
        states = opts.states,
        order_by = cfg.pull_requests.order_by,
      },
      paginate = true,
      jq = ".",
      opts = {
        stream_cb = function(data, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif data then
            local resp = utils.aggregate_pages(data, "data.repository.pullRequests.nodes")
            local pull_requests = resp.data.repository.pullRequests.nodes

            for _, pull in ipairs(pull_requests) do
              local entry = entry_maker.gen_from_issue(pull)

              if entry ~= nil then
                formatted_pulls[entry.ordinal] = entry
                local highlight
                if entry.obj.isDraft then
                  highlight = "OctoSymbol"
                else
                  highlight = "OctoStateOpen"
                end
                local prefix = fzf.utils.ansi_from_hl(highlight, entry.value)
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
    previewer = previewers.issue(formatted_pulls),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
    },
    winopts = {
      title = window_title,
      title_pos = "center",
    },
    actions = vim.tbl_extend("force", fzf_actions.common_open_actions(formatted_pulls), {
      [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.checkout_pr.lhs)] = function(selected)
        local entry = formatted_pulls[selected[1]]
        checkout_pull_request(entry)
      end,
    }),
  })
end
