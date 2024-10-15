local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

local function checkout_pull_request(entry)
  utils.checkout_pr(entry.obj.number)
end

return function(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end
  local filter = picker_utils.get_filter(opts, "pull_request")
  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end
  if not opts.repo then
    utils.error "Cannot find repo"
    return
  end

  local owner, name = utils.split_repo(opts.repo)
  local cfg = octo_config.values
  local order_by = cfg.pull_requests.order_by

  local query =
      graphql("pull_requests_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })

  local get_contents = function(fzf_cb)
    gh.run {
      args = {
        "api",
        "graphql",
        "--paginate",
        "--jq",
        ".",
        "-f",
        string.format("query=%s", query),
      },
      stream_cb = function(data, err)
        if err and not utils.is_blank(err) then
          utils.error(err)
          fzf_cb()
        elseif data then
          local resp = utils.aggregate_pages(data, "data.repository.pullRequests.nodes")
          local pull_requests = resp.data.repository.pullRequests.nodes

          for _, pull in ipairs(pull_requests) do
            local entry_string = entry_maker.entry_string_from_issue_or_pr(pull, function(tbl)
              local highlight
              if tbl.isDraft then
                highlight = "OctoSymbol"
              else
                highlight = "OctoStateOpen"
              end
              return fzf.utils.ansi_from_hl(highlight, tbl.number)
            end)

            if entry_string ~= nil then
              fzf_cb(entry_string)
            end
          end
        end
      end,
      cb = function()
        fzf_cb()
      end,
    }
  end

  local checkout_pr_mapping = utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.checkout_pr.lhs)

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    previewer = previewers.pr_and_issue(),
    fzf_opts = {
      ["--info"] = "default",
      ["--multi"] = true,
      ["--delimiter"] = " ",
      ["--with-nth"] = "4..",
    },
    actions = vim.tbl_extend("force", fzf_actions.common_open_actions_v2(), {
      [checkout_pr_mapping] = function(selected, _opts)
        local split = vim.split(selected[1], " ")
        utils.checkout_pr(split[3])
      end,
    }),
    _fmt = {
      from = function(entry)
        local split = vim.split(entry, " ")
        return split[1] .. ":1:1:" .. table.concat(split, " ", 2)
      end,
    },
    parse_entry = function(entry)
      local split = vim.split(entry, " ")
      local number = split[4]
      local owner, name = utils.split_repo(split[3])
      return {
        kind = "pull_request",
        number = number,
        owner = owner,
        name = name,
        previewer_title = split[3],
      }
    end,
  })
end
