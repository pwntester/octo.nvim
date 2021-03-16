local api = vim.api
local constants = require "octo.constants"
local util = require "octo.util"
local gh = require "octo.gh"
local graphql = require "octo.graphql"
local format = string.format
local json = {
  parse = vim.fn.json_decode
}

local M = {}

function M.open_in_browser()
  local repo, number = util.get_repo_number()
  local bufname = vim.fn.bufname()
  local _, kind = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if kind == "pull" then
    kind = "pr"
  end
  local cmd = format("gh %s view --web -R %s %d", kind, repo, number)
  os.execute(cmd)
end

function M.go_to_issue()
  local _, current_repo = pcall(api.nvim_buf_get_var, 0, "repo")
  if not current_repo then return end

  local repo, number = util.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)

  if not repo or not number then
    repo = current_repo
    number = util.extract_pattern_at_cursor(constants.SHORT_ISSUE_PATTERN)
  end

  if not repo or not number then
    repo, _, number = util.extract_pattern_at_cursor(constants.URL_ISSUE_PATTERN)
  end

  if repo and number then
    local owner, name = util.split_repo(repo)
    local query = graphql("issue_kind_query", owner, name, number)
    gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            local resp = json.parse(output)
            local kind = resp.data.repository.issueOrPullRequest.__typename
            if kind == "Issue" then
              util.get_issue(repo, number)
            elseif kind == "PullRequest" then
              util.get_pull_request(repo, number)
            end
          end
        end
      }
    )
  end
end

return M
