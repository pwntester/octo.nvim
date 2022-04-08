require("octo.model.repository")
require("octo.model.octo")

-- This holds the base defintion of the (git) Repo Hosts.
local host = {}

-- RepoHost holds the base defintion of a repo host.
-- It can be used/ threated like a interface in other languages.
global type RepoHost = record
  get_pull_request: function(): any
  get_repository: function(): any

  list_issues: function(self: RepoHost, repo: Repository, filter: string, cb: function(output: string, stderr: string))

  -- Processes issues from JSON input.
  process_issues: function(self: RepoHost, opts: ProcessIssuesOpts, output: string): {Issue}, integer

  get_issue: function(self: RepoHost, repo: Repository, number: integer,  cb: function(issue: Issue, stderr: string))

  -- Has some utility functions to process or validate
  -- input specifc to a hosting provider.
  record Util
    -- validates and processes the given filter.
    get_filter: function(self: Util, opts: {string:string}, kind: OctoKind): string
  end
  util: Util

  get_user_name: function(self: RepoHost, hostname: string): string
  get_user: function(self: RepoHost): string
  set_provider: function(self: RepoHost, hostname: string)
end

global type ProcessIssuesOpts = record
  repo: Repository
  preview_title: string
  prompt_title: string
  results_title: string
end

return host
