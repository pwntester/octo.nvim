---Helper functions for debugging Octo internals
local utils = require "octo.utils"
local context = require "octo.context"

local M = {}

---Get the current Octo buffer information
function M.current_buffer()
  context.within_octo_buffer(function(buffer)
    utils.info(vim.inspect(buffer))
  end)()
end

---Get the current Octo context information
function M.globals()
  utils.info(vim.inspect {
    octo_buffers = _G.octo_buffers,
    octo_repo_issues = _G.octo_repo_issues,
    octo_pv2_fragment = _G.octo_pv2_fragment,
    OctoLastCmdOpts = _G.OctoLastCmdOpts,
  })
end

return M
