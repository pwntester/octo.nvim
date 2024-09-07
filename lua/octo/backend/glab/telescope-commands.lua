local utils = require "octo.utils"
local cli = require "octo.backend.glab.cli"
local graphql = require "octo.backend.glab.graphql"
local converters = require "octo.backend.glab.converters"
local writers = require "octo.ui.writers"

local previewers = require "octo.pickers.telescope.previewers"
local entry_maker = require "octo.pickers.telescope.entry_maker"
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
  local query
  local global_id = string.format("gid://gitlab/MergeRequest/%s", entry.obj.global_id)
  -- #233
  if entry.kind == "issue" then
    utils.error "glab doesn't have <telescope_default_issue for issues> implemented"
  elseif entry.kind == "pull_request" then
    query = graphql("pull_request_query", global_id)
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output and vim.api.nvim_buf_is_valid(bufnr) then
        local result = vim.fn.json_decode(output)
        local obj
        -- #233 Issues
        if entry.kind == "issue" then
          utils.error "glab doesn't have <telescope_default_issue for issues> implemented"
        elseif entry.kind == "pull_request" then
          obj = result.data.mergeRequest
        end
        writers.write_title(bufnr, obj.title, 1)
        -- only a subset of the actual timeline, no need to convert everything
        local converted_pull_request = converters.convert_graphql_pull_request(obj)

        writers.write_details(bufnr, converted_pull_request)
        writers.write_body(bufnr, converted_pull_request)
        writers.write_state(bufnr, converted_pull_request.state:upper(), number)
        local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
        writers.write_block(bufnr, { "", "" }, reactions_line)
        -- #233 Emojis
        --writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
        vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
      end
    end,
  }
end

--  sort: asc or desc. Default is desc.
-- #244: paginate
---@param opts table injected options
---@param cfg OctoConfig
---@param filter string
function M.telescope_pull_requests(opts, cfg, filter)
  local order_by = cfg.pull_requests.order_by
  utils.info "Fetching pull requests (this may take a while) ..."
  -- #234 configurable state=XXX? unused filter
  local url = string.format(
    "/projects/:id/merge_requests?state=opened&order_by=%s&sort=%s",
    string.lower(order_by.field),
    string.lower(order_by.direction)
  )
  cli.run {
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif not utils.is_blank(output) then
        local prs = vim.fn.json_decode(output)
        if #prs == 0 then
          utils.error(string.format("There are no matching pull requests in %s.", opts.repo))
          return
        end
        local pull_requests, max_number = converters.parse_merge_requests_output(prs, opts.repo)
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

-- #234 glab api sends a parent commit ID, but most of the time its empty. No idea why.
---@param current_review Review
---@param cb function
function M.telescope_review_commits(current_review, cb)
  local url = string.format("/projects/:id/merge_requests/%d/commits", current_review.pull_request.number)
  cli.run {
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        ---@type glab_commit[]
        local commits = vim.fn.json_decode(output)
        local results = converters.convert_commits(commits)

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

-- Select a label from the relevant group
---@param buffer OctoBuffer
---@param opts table dropdown_opts
function M.telescope_select_label(buffer, opts, cb)
  local owner, _ = utils.split_repo(buffer.repo)
  local query = graphql("labels_query", owner)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = converters.convert_labels(resp.data.group.labels).nodes
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

-- Select one of the labels the issue/pr has assigned (context: remove label from thing)
---@param buffer OctoBuffer
---@param opts table dropdown_opts
function M.telescope_select_assigned_label(buffer, opts, cb)
  local query, key
  -- #233 Issues
  if buffer:isIssue() then
    utils.error "glab doesn't have <telescope_select_assigned_label for issues> implemented"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_labels_query", buffer.node.global_id)
    key = "mergeRequest"
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = converters.convert_labels(resp.data[key].labels).nodes
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

return M
