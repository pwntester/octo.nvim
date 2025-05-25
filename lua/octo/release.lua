local gh = require "octo.gh"
local M = {}

---GraphQL only accepts tag names as a filter, and this helps with the conversion.
---@param info {owner: string, repo: string, release_id: string}
---@param on_success fun(tag_name: string): nil
function M.get_tag_from_release_id(info, on_success)
  local owner, name, number = info.owner, info.repo, info.release_id
  gh.api.get {
    "/repos/{owner}/{repo}/releases/{release_id}",
    format = { owner = owner, repo = name, release_id = number },
    jq = ".tag_name",
    opts = {
      cb = gh.create_callback {
        success = function(tag_name)
          on_success(tag_name)
        end,
      },
    },
  }
end

return M
