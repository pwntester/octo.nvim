local utils = require "octo.utils"
local graphql = require "octo.backend.gh.graphql"
local cli = require "octo.backend.gh.cli"
local window = require "octo.ui.window"
local writers = require "octo.ui.writers"

local M = {}

function M.pull(opts, cb)
    local repo = opts["repo"]
    local number = opts["number"]

    local owner, name = utils.split_repo(repo)

    local query = graphql("pull_request_query", owner, name, number)
    local key = "pullRequest"

    cli.run {
        args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = utils.aggregate_pages(output, string.format("data.repository.%s.timelineItems.nodes", key))
                local obj = resp.data.repository[key]
                cb(obj)
            end
        end,
    }
end

function M.issue(opts, cb)
    local repo = opts["repo"]
    local number = opts["number"]

    local owner, name = utils.split_repo(repo)

    local query = graphql("issue_query", owner, name, number)
    local key = "issue"

    cli.run {
        args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = utils.aggregate_pages(output, string.format("data.repository.%s.timelineItems.nodes", key))
                local obj = resp.data.repository[key]
                cb(obj)
            end
        end,
    }
end

function M.repo(opts, cb)
    local repo = opts["repo"]

    local owner, name = utils.split_repo(repo)

    local query = graphql("repository_query", owner, name)

    cli.run {
        args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = vim.fn.json_decode(output)
                local obj = resp.data.repository
                cb(obj)
            end
        end,
    }
end

function M.reactions_popup(opts, _)
    local id = opts["id"]

    local query = graphql("reactions_for_object_query", id)

    cli.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = vim.fn.json_decode(output)
                local reactions = {}
                local reactionGroups = resp.data.node.reactionGroups

                for _, reactionGroup in ipairs(reactionGroups) do
                    local users = reactionGroup.users.nodes
                    local logins = {}

                    for _, user in ipairs(users) do
                        table.insert(logins, user.login)
                    end

                    if #logins > 0 then
                        reactions[reactionGroup.content] = logins
                    end
                end

                local popup_bufnr = vim.api.nvim_create_buf(false, true)
                local lines_count, max_length = writers.write_reactions_summary(popup_bufnr, reactions)

                window.create_popup {
                    bufnr = popup_bufnr,
                    width = 4 + max_length,
                    height = 2 + lines_count,
                }
            end
        end,
    }
end

function M.user_popup(opts, _)
    local login = opts["login"]

    local query = graphql("user_profile_query", login)

    cli.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = vim.fn.json_decode(output)
                local user = resp.data.user
                local popup_bufnr = vim.api.nvim_create_buf(false, true)
                local lines, max_length = writers.write_user_profile(popup_bufnr, user)

                window.create_popup {
                    bufnr = popup_bufnr,
                    width = 4 + max_length,
                    height = 2 + lines,
                }
            end
        end,
    }
end

function M.link_popup(opts, _)
    local repo = opts["repo"]
    local number = opts["number"]

    local owner, name = utils.split_repo(repo)
    local query = graphql("issue_summary_query", owner, name, number)

    cli.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = vim.fn.json_decode(output)
                local issue = resp.data.repository.issueOrPullRequest
                local popup_bufnr = vim.api.nvim_create_buf(false, true)
                local max_length = 80
                local lines = writers.write_issue_summary(popup_bufnr, issue, { max_length = max_length })

                window.create_popup {
                    bufnr = popup_bufnr,
                    width = max_length,
                    height = 2 + lines,
                }
            end
        end,
    }
end

function M.go_to_issue(opts, _)
    local repo = opts["repo"]
    local number = opts["number"]

    local owner, name = utils.split_repo(repo)
    local query = graphql("issue_kind_query", owner, name, number)

    cli.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
                vim.api.nvim_err_writeln(stderr)
            elseif output then
                local resp = vim.fn.json_decode(output)
                local kind = resp.data.repository.issueOrPullRequest.__typename

                if kind == "Issue" then
                    utils.get_issue(repo, number)
                elseif kind == "PullRequest" then
                    utils.get_pull_request(repo, number)
                end
            end
        end,
    }
end

M.functions = {
    ["pull"] = M.pull,
    ["issue"] = M.issue,
    ["repo"] = M.repo,
    ["reactions_popup"] = M.reactions_popup,
    ["user_popup"] = M.user_popup,
    ["link_popup"] = M.link_popup,
    ["go_to_issue"] = M.go_to_issue
}

return M
