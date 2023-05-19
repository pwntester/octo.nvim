local actions = require "octo.pickers.fzf-lua.pickers.actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

return function (opts)
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
  local cfg = octo_config.get_config()
  local order_by = cfg.issues.order_by
  local query = graphql("issues_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  utils.info "Fetching issues (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.issues.nodes")
        local issues = resp.data.repository.issues.nodes
        if #issues == 0 then
          utils.error(string.format("There are no matching issues in %s.", opts.repo))
          return
        end

        local formatted_issues = {}
        local titles = {}

        for _, issue in ipairs(issues) do
          local entry = entry_maker.gen_from_issue(issue)

          if entry ~= nil then
            formatted_issues[entry.ordinal] = entry
            table.insert(titles, {
              prefix = fzf.utils.ansi_from_hl('Comment', entry.value) .. ' ',
              contents = { entry.obj.title }
            })
          end
        end

        fzf.fzf_exec(titles, {
          prompt = opts.prompt_title or "",
          previewer = previewers.issue(formatted_issues),
          fzf_opts = {
            ["--no-multi"]  = "", -- TODO this can support multi, maybe.
            ['--header'] = opts.results_title,
            ['--preview-window'] = 'nohidden,right,50%',
          },
          actions = actions.common_open_actions(formatted_issues),
        })
      end
    end,
  }
end

