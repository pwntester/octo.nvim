local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local fzf = require "fzf-lua"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

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

  local cfg = octo_config.values
  local order_by = cfg.issues.order_by
  local formatted_issues = {}

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_issues"]
    func(formatted_issues, opts.repo, order_by, filter, fzf_cb)
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    previewer = previewers.issue(formatted_issues),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--header"] = opts.results_title,
      ["--info"] = "default",
    },
    winopts = {
      title = opts.window_title or "Issues",
      title_pos = "center",
    },
    actions = fzf_actions.common_open_actions(formatted_issues),
  })
end
