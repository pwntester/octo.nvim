local gh = require "octo.backend.gh"
local glab = require "octo.backend.glab"
local utils = require "octo.utils"
local config = require "octo.config"

local M = {}

local backend = {
  ["gh"] = gh,
  ["glab"] = glab,
}

---@return "gh" | "glab"
local function get_cli()
  local remote_hostname = utils.get_remote_host()
  local cli
  if string.find(remote_hostname, "github") then
    cli = config.values.gh_cmd
  else
    cli = config.values.glab_cmd
  end
  return cli
end

function M.get_funcs()
  local cli = get_cli()
  return backend[cli].functions
end

---@return boolean
function M.available_executable()
  local cli = get_cli()
  if not vim.fn.executable(cli) then
    utils.error("Executable not found using path: " .. cli)
    return false
  end
  return true
end

return M
