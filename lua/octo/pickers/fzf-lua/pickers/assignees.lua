local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"

return function(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_select_assignee"]
    func(buffer, fzf_cb)
  end

  fzf.fzf_exec(
    get_contents,
    vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
      fzf_opts = {
        ["--no-multi"] = "", -- TODO this can support multi, maybe.
        ["--delimiter"] = "' '",
        ["--with-nth"] = "2..",
      },
      actions = {
        ["default"] = function(selected)
          local id, _ = unpack(vim.split(selected[1], " "))
          cb(id)
        end,
      },
    })
  )
end
