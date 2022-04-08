require("octo.host.host")
require("octo.model.octo")
local graphql = require("octo.host.github.graphql")
local gh = require("octo.gh")
local utils = require("octo.utils")

local record GitHubIssuesQuery
  record Data
    record Repository
      record Node
        record GitHubIssue
          number: integer
          title: string
        end
        nodes: {GitHubIssue}
      end
      issues: Node
    end
    repository: Repository
  end
  data: Data
end

local record GitHubUser
  login: string
end

local record GitHubReactionGroup
  enum ReactionContent
    "CONFUSED"
    "EYES"
    "HEART"
    "HOORAY"
    "LAUGH"
    "ROCKET"
    "LAUGH"
    "ROCKET"
    "THUMBS_DOWN"
    "THUMBS_UP"
  end
  content: ReactionContent

  viewerHasReacted: boolean
  record Users
    totalCount: integer
  end
  users: Users
end

local record GitHubIssueQuery
  record Data
    record Project
      record GitLabIssue
        number: integer
        title: string
        body: string

        author: GitHubUser
        url: string
        milestone: Milestone
        createdAt: string
        closedAt: string
        updatedAt: string
        state: IssueState

        viewerCanUpdate: boolean
        viewerDidAuthor: boolean

        reactionGroups: {GitHubReactionGroup}

        record UserNode
          nodes: {GitHubUser}
        end
        assignees: UserNode
        participants: UserNode

        --[[
      projectCards(last: 20) {
        nodes {
          id
          state
          column {
            name
          }
          project {
            name
          }
        }
      }
        --]]

        record TimelineItems
          nodes: {TimelineItem}
        end
        timelineItems: TimelineItems

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
    repository: Project
  end
  data: Data
end

local function convertToUser(u: GitHubUser): User
  local user: User = {}
  user.username = u.login

  return user
end

local function convertToUsers(u: {GitHubUser}): {User}
  local users: {User} = {}

  for i, user in ipairs(u) do
    users[i] = {}
    users[i].username = user.login
  end

  return users
end

local M: RepoHost = {
  util = {}
}

function M:get_user_name(): string
  return gh.get_user_name()
end

function M:list_issues(repo: Repository, filter: string, cb: function(output: string, stderr: string))
  if filter == nil then
    filter = ""
  end

  local query = graphql.g("issues_query", repo.owner, repo.name, filter, { escape = false })
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = cb,
  }
end

function M:get_issue(repo: Repository, number: integer,  cb: function(issue: Issue, stderr: string))
  local query = graphql.g("issue_query", repo.owner, repo.name, number)
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output: string, stderr: string)
      if stderr and not utils.is_blank(stderr) then
        cb(nil, stderr)
        return
      end

      local result = vim.fn.json_decode(output) as GitHubIssueQuery
      local obj = result.data.repository.issue
      local issue: Issue = {}

      issue.title = obj.title
      issue.author = convertToUser(obj.author)
      issue.participants = convertToUsers(obj.participants.nodes)
      issue.milestone = obj.milestone
      issue.createdAt = obj.createdAt
      issue.updatedAt = obj.updatedAt
      issue.closedAt = obj.closedAt
      issue.description = obj.body
      issue.viewerDidAuthor = obj.viewerDidAuthor
      issue.viewerCanUpdate = obj.viewerCanUpdate
      issue.state = obj.state
      issue.reactionGroups = obj.reactionGroups as {ReactionGroup}

      issue.assignees = {}
      if obj.assignees and #obj.assignees.nodes > 0 then
        for i, assignee in ipairs(obj.assignees.nodes) do
          issue.assignees[i] = convertToUser(assignee)
        end
      end

      issue.labels = {}
      if obj.labels and #obj.labels.nodes > 0 then
        for i, label in ipairs(obj.labels.nodes) do
          issue.labels[i] = label as Label
        end
      end

      issue.timelineItems = {}
      if obj.timelineItems and #obj.timelineItems.nodes > 0 then
          for i, item in ipairs(obj.timelineItems.nodes) do
            issue.timelineItems[i] = item
            issue.timelineItems[i].itemType = item.__typename as TimelineItemType
          end
      end

      cb(issue, stderr)
    end,
  }
end

function M:process_issues(opts: ProcessIssuesOpts, output: string): {Issue}, integer
  local resp = utils.aggregate_pages(output, "data.repository.issues.nodes") as GitHubIssuesQuery
  local issues = resp.data.repository.issues.nodes
  if #issues == 0 then
    utils.notify(string.format("There are no matching issues in %s.", opts.repo), 2)
    return
  end

  local max_number = -1
  local ret: {Issue} = {}
  for i, issue in ipairs(issues) do
    if #tostring(issue.number) > max_number then
      max_number = #tostring(issue.number)
    end

    ret[i] = {}
    ret[i].__typename = "Issue"
    ret[i].repo = opts.repo
    ret[i].id = issue.number
    ret[i].title = issue.title
  end

  opts.preview_title = opts.preview_title or ""
  opts.prompt_title = opts.prompt_title or ""
  opts.results_title = opts.results_title or ""

  return ret, max_number
end

function M.util:get_filter(opts: {string:string}, kind: OctoKind): string
  local filter = ""
  local allowed_values: {string} = {}
  if kind == "issue" then
    allowed_values = { "since", "createdBy", "assignee", "mentioned", "labels", "milestone", "states" }
  elseif kind == "pull_request" then
    allowed_values = { "baseRefName", "headRefName", "labels", "states" }
  end

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
      val = vim.fn.json_encode(val)
      val = string.gsub(val as string, '"OPEN"', "OPEN")
      val = string.gsub(val as string, '"CLOSED"', "CLOSED")
      val = string.gsub(val as string, '"MERGED"', "MERGED")
      filter = filter .. value .. ":" .. (val as string) .. ","
    end
  end

  return filter
end

return M
