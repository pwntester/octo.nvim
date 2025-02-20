local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local query, key
  if buffer:isIssue() then
    query = graphql("issue_assignees_query", buffer.owner, buffer.name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_assignees_query", buffer.owner, buffer.name, buffer.number)
    key = "pullRequest"
  end

  local get_contents = function(fzf_cb)
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = vim.json.decode(output)
          local assignees = resp.data.repository[key].assignees.nodes

          for _, user in ipairs(assignees) do
            fzf_cb(string.format("%s %s", user.id, user.login))
          end
        end

        fzf_cb()
      end,
    }
  end

  fzf.fzf_exec(
    get_contents,
    vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
      fzf_opts = {
        ["--no-multi"] = "", -- TODO this can support multi, maybe.
        ["--delimiter"] = "' '",
        ["--with-nth"] = "2..",
      },
      actions = {
        ["default"] = function(selected)
          local id, _ = unpack(vim.split(selected[1], " "))
          cb(id)
        end,
      },
    })
  )
end
