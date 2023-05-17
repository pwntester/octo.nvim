local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local octo_config = require "octo.config"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"

local function checkout_pull_request(entry)
  utils.checkout_pr(entry.obj.number)
end

return function (opts)
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
  local cfg = octo_config.get_config()
  local order_by = cfg.pull_requests.order_by
  local query =
    graphql("pull_requests_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  utils.info "Fetching pull requests (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.pullRequests.nodes")
        local pull_requests = resp.data.repository.pullRequests.nodes
        if #pull_requests == 0 then
          utils.error(string.format("There are no matching pull requests in %s.", opts.repo))
          return
        end
        local formatted_pulls = {}
        local titles = {}

        for _, pull in ipairs(pull_requests) do
          local entry = entry_maker.gen_from_issue(pull)

          if entry ~= nil then
            formatted_pulls[entry.ordinal] = entry
            table.insert(titles, { prefix = entry.number, contents = { entry.ordinal } })
          end
        end

        fzf.fzf_exec(titles, {
          prompt = opts.prompt_title or "",
          -- TODO What is this?
          -- opts.preview_title = opts.preview_title or ""
          previewer = previewers.issue(formatted_pulls),
          actions = {
            ['default'] = function (selected)
              local entry = formatted_pulls[selected[1]]
              picker_utils.open('default', entry)
            end,
            ['ctrl-v'] = function (selected)
              local entry = formatted_pulls[selected[1]]
              picker_utils.open('vertical', entry)
            end,
            ['ctrl-s'] = function (selected)
              local entry = formatted_pulls[selected[1]]
              picker_utils.open('horizontal', entry)
            end,
            ['ctrl-t'] = function (selected)
              local entry = formatted_pulls[selected[1]]
              picker_utils.open('tab', entry)
            end,
            ['ctrl-b'] = function (selected)
              picker_utils.open_in_browser(formatted_pulls[selected[1]])
            end,
            ['ctrl-y'] = function (selected)
              picker_utils.copy_url(formatted_pulls[selected[1]])
            end,

            ['ctrl-o'] = function (selected)
              local entry = formatted_pulls[selected[1]]
              checkout_pull_request(entry)
            end,
          },
        })

      end
    end,
  }
end


