require("octo.host.host")
require("octo.model.octo")
local graphql = require("octo.host.gitlab.graphql")
local glab = require("octo.host.gitlab.glab")
local utils = require("octo.utils")

local record GitLabIssuesQuery
  record Data
    record Project
      record Node
        record GitLabIssue
          id: integer
          iid: integer
          title: string
        end
        nodes: {GitLabIssue}
      end
      issues: Node
    end
    project: Project
  end
  data: Data
end

local record GitLabIssueQuery
  record Data
    record Project
      record GitLabIssue
        id: integer
        iid: integer
        title: string

        author: User
        milestone: Milestone
        createdAt: string
        closedAt: string
        updatedAt: string
        description: string
        state: IssueState
        webUrl: string

        record UserPermission
          adminIssue: boolean
          updateIssue: boolean
        end
        userPermissions: UserPermission

        record UserNode
          nodes: {User}
        end
        assignees: UserNode

        record LabelNode
          record GitLabLabel
            textColor: string
            title: string
          end
          nodes: {GitLabLabel}
        end
        labels: LabelNode
      end
      issue: GitLabIssue
    end
    project: Project
  end
  data: Data
end

local M: RepoHost = {
  util = {}
}

function M:get_user_name(): string
  return glab.get_user_name()
end

-- function M:get_user(_: string): string
--   -- local query = graphql.g("current_user")
--   -- glab.run {
--   --   hostname = hostname,
--   --   args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
--   --   cb = function(output: string, stderr: string)
      
--   --   end,
--   -- }
--   return ""
-- end

function M:list_issues(repo: Repository, filter: string, cb: function(output: string, stderr: string))
  if filter == nil then
    filter = ""
  end

  local query = graphql.g("issues_query", repo.full_path, filter, { escape = false })
  glab.run {
    hostname = repo.hostname,
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = cb,
  }
end

function M:get_issue(repo: Repository, number: integer,  cb: function(issue: Issue, stderr: string))
  local query = graphql.g("issue_query", repo.full_path, number)
  glab.run {
    hostname = repo.hostname,
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output: string, stderr: string)
      if stderr and not utils.is_blank(stderr) then
        cb(nil, stderr)
        return
      end

      local result = vim.fn.json_decode(output) as GitLabIssueQuery
      local obj = result.data.project.issue
      local issue: Issue = {}

      issue.title = obj.title
      issue.author = obj.author
      issue.milestone = obj.milestone
      issue.createdAt = obj.createdAt
      issue.updatedAt = obj.updatedAt
      issue.closedAt = obj.closedAt
      issue.description = obj.description
      issue.viewerDidAuthor = false -- TODO: Implement me
      issue.viewerCanUpdate = obj.userPermissions.updateIssue or obj.userPermissions.adminIssue
      issue.state = obj.state
      issue.reactionGroups = {}
      issue.url = obj.webUrl

      issue.assignees = {}
      if obj.assignees and #obj.assignees.nodes > 0 then
        for i, assignee in ipairs(obj.assignees.nodes) do
          issue.assignees[i] = assignee
        end
      end

      issue.labels = {}
      if obj.labels and #obj.labels.nodes > 0 then
        for i, label in ipairs(obj.labels.nodes) do
          issue.labels[i] = {}
          issue.labels[i].color = label.textColor
          issue.labels[i].name = label.title
        end
      end

      cb(issue, stderr)
    end,
  }
end

function M:process_issues(opts: ProcessIssuesOpts, output: string): {Issue}, integer
  local resp = utils.aggregate_pages(output, "data.project.issues.nodes") as GitLabIssuesQuery
  local issues = resp.data.project.issues.nodes
  if #issues == 0 then
    utils.notify(string.format("There are no matching issues in %s.", opts.repo), 2)
    return
  end

  local max_number = -1
  local ret: {Issue} = {}
  for i, issue in ipairs(issues) do
    if #tostring(issue.iid) > max_number then
      max_number = #tostring(issue.iid)
    end

    ret[i] = {}
    ret[i].__typename = "Issue"
    ret[i].repo = opts.repo
    ret[i].id = issue.iid
    ret[i].title = issue.title
  end

  opts.preview_title = opts.preview_title or ""
  opts.prompt_title = opts.prompt_title or ""
  opts.results_title = opts.results_title or ""

  return ret, max_number
end

function M.util:get_filter(opts: {string:string}, kind: OctoKind): string
  local type convTarget = enum
    "string"
    "string_array"
  end

  local filter = ""
  local allowed_values = {}
  local map: {string:{string,convTarget}} = {} -- for convenience, we auto. convert some filters
  if kind == "issue" then
    allowed_values = { "createdAfter", "author", "assignee", "labels", "milestone", "states" }
    map = {
      ["assignee"] = {"assigneeUsernames", "string_array"},
      ["assignees"] = {"assigneeUsernames", "string_array"},
      ["labels"] = {"labelName", "string_array"},
      ["author"] = {"authorUsername", "string"},
      ["milestone"] = {"milestoneTitle", "string"},
      ["states"] = {"state", "string"},
    }
  elseif kind == "pull_request" then
    -- TODO: Update me
    allowed_values = { "baseRefName", "headRefName", "labels", "states" }
  end

  local hasStateFilter: boolean = false

  for _, value in ipairs(allowed_values) do
    if opts[value] then
      local val: any
      if #vim.split(opts[value], ",") > 1 then
        -- list
        val = vim.split(opts[value], ",")
      else
        -- string
        val = opts[value]
      end

      if value == "state" or value == "states" then
        hasStateFilter = true
      end
      if map[value] then
        local target: {string,convTarget} = map[value]
        value = target[1]

        if target[2] == "string_array" then
          -- NOTE: There may be complications with the above list
        end
      end
      val = vim.fn.json_encode(val) as string
      val = string.gsub(val as string, '"all"', "all")
      val = string.gsub(val as string, '"OPEN"', "opened")
      val = string.gsub(val as string, '"opened"', "opened")
      val = string.gsub(val as string, '"closed"', "closed")
      val = string.gsub(val as string, '"locked"', "locked")

      filter = filter .. value .. ":" .. (val as string) .. ","
    end
  end

  if not hasStateFilter then
    filter = filter .. "state:opened,"
  end

  return filter
end

return M
