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
    local func = backend.get_funcs()["fzf_lua_select_assigned_label"]
    func(buffer, fzf_cb)
  end

  fzf.fzf_exec(
    get_contents,
    vim.tbl_deep_extend("force", picker_utils.multi_dropdown_opts, {
      fzf_opts = {
        ["--delimiter"] = "' '",
        ["--with-nth"] = "2..",
      },
      actions = {
        ["default"] = function(selected)
          for _, row in ipairs(selected) do
            local id, _ = unpack(vim.split(row, " "))
            cb(id)
          end
        end,
      },
    })
  )
end
