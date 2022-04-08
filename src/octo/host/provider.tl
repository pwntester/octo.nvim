require("octo.host.host")

local prov = require("octo.host.helper")

-- A generic host provider which loads the specific
-- host provider implementation when it's required.
local M: RepoHost = {
  util = {}
}
local provider: RepoHost -- Carefully use this variable to not introduce a race condition..

local function notify(msg: string, kind: integer)
  vim.notify(msg, kind, { title = "Octo.nvim" })
end

function M:set_provider(hostname: string)
  local p = prov.resolve(hostname)
  if not p then
    notify("Unable to resolve provider for hostname " .. hostname, 2)
    return
  end

  provider = p
end

function M:list_issues(repo: Repository, filter: string, cb: function(output: string, stderr: string))
  M:set_provider(repo.hostname)
  provider:list_issues(repo, filter, cb)
end

function M:get_issue(repo: Repository, number: integer,  cb: function(issue: Issue, stderr: string))
  provider:get_issue(repo, number, cb)
end

function M:get_user_name(): string
  return provider:get_user_name()
end

function M:process_issues(opts: ProcessIssuesOpts, output: string): {Issue}, integer
  -- NOTE: We assume that the repo host has been set previously, e. g., by list_issues()
  return provider:process_issues(opts, output)
end

function M.util:get_filter(opts: {string:string}, kind: OctoKind): string
  return provider.util:get_filter(opts, kind)
end

return M
