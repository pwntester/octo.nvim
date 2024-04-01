local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local fzf = require "fzf-lua"
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

  local cfg = octo_config.values
  local order_by = cfg.pull_requests.order_by

  local formatted_pulls = {}

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_pull_requests"]
    func(formatted_pulls, opts.repo, order_by, filter, fzf_cb)
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    previewer = previewers.issue(formatted_pulls),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
    },
    actions = vim.tbl_extend("force", fzf_actions.common_open_actions(formatted_pulls), {
      [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.checkout_pr.lhs)] = function(selected)
        local entry = formatted_pulls[selected[1]]
        checkout_pull_request(entry)
      end,
    }),
  })
end
