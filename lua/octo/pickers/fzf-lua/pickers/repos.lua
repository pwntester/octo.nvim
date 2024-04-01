local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

return function(opts)
  opts = opts or {}
  if not opts.login then
    if vim.g.octo_viewer then
      opts.login = vim.g.octo_viewer
    else
      local backend = require "octo.backend"
      local remote_hostname = utils.get_remote_host()
      local func = backend.get_funcs()["get_user_name"]
      opts.login = func(remote_hostname)
    end
  end

  local formatted_repos = {}

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_repos"]
    func(formatted_repos, opts.login, fzf_cb)
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
