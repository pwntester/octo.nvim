local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"

return function(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end
  local filter = picker_utils.get_filter(opts, "issue")
  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end
  if not opts.repo then
    utils.error "Cannot find repo"
    return
  end

  local owner, name = utils.split_repo(opts.repo)
  local cfg = octo_config.values
  local order_by = cfg.issues.order_by

  local query = graphql("issues_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })

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
          local resp = utils.aggregate_pages(data, "data.repository.issues.nodes")
          local issues = resp.data.repository.issues.nodes

          for _, issue in ipairs(issues) do
            local entry_string = entry_maker.entry_string_from_issue_or_pr(issue, function(tbl)
              return fzf.utils.ansi_from_hl("Comment", tbl.number)
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

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    previewer = previewers.pr_and_issue(),
    fzf_opts = {
      ["--header"] = opts.results_title,
      ["--info"] = "default",
      ["--multi"] = true,
      ["--delimiter"] = " ",
      ["--with-nth"] = "4..",
    },
    winopts = {
      title = opts.window_title or "Issues",
      title_pos = "center",
    },
    actions = fzf_actions.common_buffer_actions_v2(),
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
        kind = "issue",
        number = number,
        owner = owner,
        name = name,
        previewer_title = split[3],
      }
    end,
  })
end
