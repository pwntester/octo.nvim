local utils = require "octo.utils"
local cli = require "octo.backend.gh.cli"
local graphql = require "octo.backend.gh.graphql"
local writers = require "octo.ui.writers"

local previewers = require "octo.pickers.telescope.previewers"
local entry_maker = require "octo.pickers.telescope.entry_maker"
local pv_utils = require "telescope.previewers.utils"
local conf = require("telescope.config").values
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local actions = require "telescope.actions"
local action_set = require "telescope.actions.set"
local action_state = require "telescope.actions.state"

local M = {}

---@param entry table
---@param bufnr integer
function M.telescope_default_issue(entry, bufnr)
  local number = entry.value
  local owner, name = utils.split_repo(entry.repo)
  local query
  if entry.kind == "issue" then
    query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
  elseif entry.kind == "pull_request" then
    query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output and vim.api.nvim_buf_is_valid(bufnr) then
        local result = vim.fn.json_decode(output)
        local obj
        if entry.kind == "issue" then
          obj = result.data.repository.issue
        elseif entry.kind == "pull_request" then
          obj = result.data.repository.pullRequest
        end
        writers.write_title(bufnr, obj.title, 1)
        writers.write_details(bufnr, obj)
        writers.write_body(bufnr, obj)
        writers.write_state(bufnr, obj.state:upper(), number)
        local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
        writers.write_block(bufnr, { "", "" }, reactions_line)
        writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
        vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
      end
    end,
  }
end

---@param entry table
---@param repo string
---@param bufname string
---@param bufnr integer
function M.telescope_default_commit(entry, repo, bufname, bufnr)
  local url = string.format("/repos/%s/commits/%s", repo, entry.value)
  local cmd = { "gh", "api", "--paginate", url, "-H", "Accept: application/vnd.github.v3.diff" }
  pv_utils.job_maker(cmd, bufnr, {
    value = entry.value,
    bufname = bufname,
    mode = "append",
    callback = function(bufnr, _)
      vim.api.nvim_buf_set_option(bufnr, "filetype", "diff")
      vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoDetailsLabel", 0, 0, string.len "Commit:")
      vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoDetailsLabel", 1, 0, string.len "Author:")
      vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoDetailsLabel", 2, 0, string.len "Date:")
    end,
  })
end

---@param opts table injected options
---@param cfg OctoConfig
---@param filter string
function M.telescope_issues(opts, cfg, filter)
  local owner, name = utils.split_repo(opts.repo)
  local order_by = opts.cfg.issues.order_by

  local query = graphql("issues_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  utils.info "Fetching issues (this may take a while) ..."
  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.issues.nodes")
        local issues = resp.data.repository.issues.nodes
        if #issues == 0 then
          utils.error(string.format("There are no matching issues in %s.", opts.repo))
          return
        end
        local max_number = -1
        for _, issue in ipairs(issues) do
          if #tostring(issue.number) > max_number then
            max_number = #tostring(issue.number)
          end
        end
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = issues,
              entry_maker = entry_maker.gen_from_issue(max_number),
            },
            sorter = conf.generic_sorter(opts),
            previewer = previewers.issue.new(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(function(prompt_bufnr, type)
                opts.open(type)(prompt_bufnr)
              end)
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, opts.open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, opts.copy_url())
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param opts table injected options
---@param privacy string
function M.telescope_gists(opts, privacy)
  local query = graphql("gists_query", privacy)
  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
        local gists = resp.data.viewer.gists.nodes
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = gists,
              entry_maker = entry_maker.gen_from_gist(),
            },
            previewer = previewers.gist.new(opts),
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, map)
              map("i", "<CR>", opts.open_gist)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param opts table injected options
---@param cfg OctoConfig
---@param filter string
function M.telescope_pull_requests(opts, cfg, filter)
  local owner, name = utils.split_repo(opts.repo)
  local order_by = cfg.pull_requests.order_by

  local query =
    graphql("pull_requests_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  utils.info "Fetching pull requests (this may take a while) ..."
  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.pullRequests.nodes")
        local pull_requests = resp.data.repository.pullRequests.nodes
        if #pull_requests == 0 then
          utils.error(string.format("There are no matching pull requests in %s.", opts.repo))
          return
        end
        local max_number = -1
        for _, pull in ipairs(pull_requests) do
          if #tostring(pull.number) > max_number then
            max_number = #tostring(pull.number)
          end
        end
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = pull_requests,
              entry_maker = entry_maker.gen_from_issue(max_number),
            },
            sorter = conf.generic_sorter(opts),
            previewer = previewers.issue.new(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(function(prompt_bufnr, type)
                opts.open(type)(prompt_bufnr)
              end)
              map("i", cfg.picker_config.mappings.checkout_pr.lhs, opts.checkout_pull_request())
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, opts.open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, opts.copy_url())
              map("i", cfg.picker_config.mappings.merge_pr.lhs, opts.merge_pull_request())
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param open_preview_buffer function
function M.telescope_commits(buffer, open_preview_buffer)
  -- TODO: graphql
  local url = string.format("repos/%s/pulls/%d/commits", buffer.repo, buffer.number)
  cli.run {
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.fn.json_decode(output)
        pickers
          .new({}, {
            prompt_title = false,
            results_title = false,
            preview_title = false,
            finder = finders.new_table {
              results = results,
              entry_maker = entry_maker.gen_from_git_commits(),
            },
            sorter = conf.generic_sorter {},
            previewer = previewers.commit.new { repo = buffer.repo },
            attach_mappings = function()
              action_set.select:replace(function(prompt_bufnr, type)
                open_preview_buffer(type)(prompt_bufnr)
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param current_review Review
---@param cb function
function M.telescope_review_commits(current_review, cb)
  -- TODO: graphql
  local url =
    string.format("repos/%s/pulls/%d/commits", current_review.pull_request.repo, current_review.pull_request.number)
  cli.run {
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.fn.json_decode(output)

        -- add a fake entry to represent the entire pull request
        table.insert(results, {
          sha = current_review.pull_request.right.commit,
          commit = {
            message = "[[ENTIRE PULL REQUEST]]",
            author = {
              name = "",
              email = "",
              date = "",
            },
          },
          parents = {
            {
              sha = current_review.pull_request.left.commit,
            },
          },
        })

        pickers
          .new({}, {
            prompt_title = false,
            results_title = false,
            preview_title = false,
            finder = finders.new_table {
              results = results,
              entry_maker = entry_maker.gen_from_git_commits(),
            },
            sorter = conf.generic_sorter {},
            previewer = previewers.commit.new { repo = current_review.pull_request.repo },
            attach_mappings = function()
              action_set.select:replace(function(prompt_bufnr)
                local commit = action_state.get_selected_entry(prompt_bufnr)
                local right = commit.value
                local left = commit.parent
                actions.close(prompt_bufnr)
                cb(right, left)
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param open_preview_buffer function
function M.telescope_changed_files(buffer, open_preview_buffer)
  local url = string.format("repos/%s/pulls/%d/files", buffer.repo, buffer.number)
  cli.run {
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.fn.json_decode(output)
        pickers
          .new({}, {
            prompt_title = false,
            results_title = false,
            preview_title = false,
            finder = finders.new_table {
              results = results,
              entry_maker = entry_maker.gen_from_git_changed_files(),
            },
            sorter = conf.generic_sorter {},
            previewer = previewers.changed_files.new { repo = buffer.repo, number = buffer.number },
            attach_mappings = function()
              action_set.select:replace(function(prompt_bufnr, type)
                open_preview_buffer(type)(prompt_bufnr)
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param prompt string
function M.telescope_search(prompt)
  local query = graphql("search_query", prompt)
  return cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
end

---@param buffer OctoBuffer
---@param dropdown_opts table
---@param cb function
function M.telescope_select_target_project_column(buffer, dropdown_opts, cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query = graphql("projects_query", owner, name, vim.g.octo_viewer, owner)

  cli.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    cb = function(output)
      if output then
        local resp = vim.fn.json_decode(output)
        local projects = {}
        local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
        local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
        local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
        vim.list_extend(projects, repo_projects)
        vim.list_extend(projects, user_projects)
        vim.list_extend(projects, org_projects)
        if #projects == 0 then
          utils.error(string.format("There are no matching projects for %s.", buffer.repo))
          return
        end

        local opts = vim.deepcopy(dropdown_opts)
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = projects,
              entry_maker = entry_maker.gen_from_project(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function()
              action_set.select:replace(function(prompt_bufnr)
                local selected_project = action_state.get_selected_entry(prompt_bufnr)
                actions._close(prompt_bufnr, true)
                local opts2 = vim.deepcopy(dropdown_opts)
                pickers
                  .new(opts2, {
                    finder = finders.new_table {
                      results = selected_project.project.columns.nodes,
                      entry_maker = entry_maker.gen_from_project_column(),
                    },
                    sorter = conf.generic_sorter(opts2),
                    attach_mappings = function()
                      action_set.select:replace(function(prompt_bufnr2)
                        local selected_column = action_state.get_selected_entry(prompt_bufnr2)
                        actions.close(prompt_bufnr2)
                        cb(selected_column.column.id)
                      end)
                      return true
                    end,
                  })
                  :find()
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param opts table dropdown_opts
function M.telescope_select_label(buffer, opts, cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query = graphql("labels_query", owner, name)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = resp.data.repository.labels.nodes
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = labels,
              entry_maker = entry_maker.gen_from_label(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, _)
              actions.select_default:replace(function(prompt_bufnr)
                local selected_label = action_state.get_selected_entry(prompt_bufnr)
                actions.close(prompt_bufnr)
                cb(selected_label.label.id)
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param opts table dropdown_opts
function M.telescope_select_assigned_label(buffer, opts, cb)
  local owner, name = utils.split_repo(buffer.repo)

  local query, key
  if buffer:isIssue() then
    query = graphql("issue_labels_query", owner, name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_labels_query", owner, name, buffer.number)
    key = "pullRequest"
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = resp.data.repository[key].labels.nodes
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = labels,
              entry_maker = entry_maker.gen_from_label(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, _)
              actions.select_default:replace(function(prompt_bufnr)
                local selected_label = action_state.get_selected_entry(prompt_bufnr)
                actions.close(prompt_bufnr)
                cb(selected_label.label.id)
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param prompt string
function M.telescope_get_users(prompt)
  local query = graphql("users_query", prompt)
  return cli.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
end

---@param buffer OctoBuffer
---@param opts table dropdown_opts
function M.telescope_select_assignee(buffer, opts, cb)
  local owner, name = utils.split_repo(buffer.repo)

  local query, key
  if buffer:isIssue() then
    query = graphql("issue_assignees_query", owner, name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_assignees_query", owner, name, buffer.number)
    key = "pullRequest"
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local assignees = resp.data.repository[key].assignees.nodes
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = assignees,
              entry_maker = entry_maker.gen_from_user(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, _)
              actions.select_default:replace(function(prompt_bufnr)
                local selected_assignee = action_state.get_selected_entry(prompt_bufnr)
                actions.close(prompt_bufnr)
                cb(selected_assignee.user.id)
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

---@param opts table injected options
---@param cfg OctoConfig
function M.telescope_repos(opts, cfg)
  local query = graphql("repos_query", opts.login)

  utils.info "Fetching repositories (this may take a while) ..."
  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repositoryOwner.repositories.nodes")
        local repos = resp.data.repositoryOwner.repositories.nodes
        if #repos == 0 then
          utils.error(string.format("There are no matching repositories for %s.", opts.login))
          return
        end
        local max_nameWithOwner = -1
        local max_forkCount = -1
        local max_stargazerCount = -1
        for _, repo in ipairs(repos) do
          max_nameWithOwner = math.max(max_nameWithOwner, #repo.nameWithOwner)
          max_forkCount = math.max(max_forkCount, #tostring(repo.forkCount))
          max_stargazerCount = math.max(max_stargazerCount, #tostring(repo.stargazerCount))
        end
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = repos,
              entry_maker = entry_maker.gen_from_repo(max_nameWithOwner, max_forkCount, max_stargazerCount),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(function(prompt_bufnr, type)
                opts.open(type)(prompt_bufnr)
              end)
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, opts.open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, opts.copy_url())
              return true
            end,
          })
          :find()
      end
    end,
  }
end

return M
