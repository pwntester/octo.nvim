local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local fzf = require "fzf-lua"
local previewers = require "octo.pickers.fzf-lua.previewers"

return function(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end

  local formatted_files = {}

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_changed_files"]
    func(formatted_files, buffer, fzf_cb)
  end

  fzf.fzf_exec(get_contents, {
    prompt = opts.prompt_title or "",
    fzf_opts = {
      ["--delimiter"] = "' '",
      ["--info"] = "default",
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--with-nth"] = "2..",
    },
    previewer = previewers.changed_files(formatted_files),
    actions = fzf_actions.common_buffer_actions(formatted_files),
  })
end
