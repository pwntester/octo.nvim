local gh = require "octo.gh"
local M = {}

---GraphQL only accepts tag names as a filter, and this helps with the conversion.
---@param info {owner: string, repo: string, release_id: string}
---@param on_success? fun(tag_name: string): nil Do not provide if synchronous
---@return string|nil
function M.get_tag_from_release_id(info, on_success)
  local owner, name, number = info.owner, info.repo, info.release_id
  local mode = on_success and "async" or "sync"
  local output = gh.api.get {
    "/repos/{owner}/{repo}/releases/{release_id}",
    format = { owner = owner, repo = name, release_id = number },
    jq = ".tag_name",
    opts = {
      mode = mode --[[@as "sync"]],
      cb = gh.create_callback {
        success = function(tag_name)
          assert(on_success, "on_success should be defined")
          on_success(tag_name)
        end,
      },
    },
  }
  return output
end

return M
