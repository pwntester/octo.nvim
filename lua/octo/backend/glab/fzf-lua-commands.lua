local utils = require "octo.utils"
local cli = require "octo.backend.glab.cli"
local graphql = require "octo.backend.glab.graphql"
local converters = require "octo.backend.glab.converters"
local writers = require "octo.ui.writers"

local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"

local M = {}

---@param entry table
---@param tmpbuf integer bufnr
function M.fzf_lua_default_issue(entry, tmpbuf)
  local kind = entry.kind
  local number = entry.value
  local gid = entry.obj.global_id
  local query
  local global_id = string.format("gid://gitlab/MergeRequest/%s", gid)
  -- #233
  if kind == "issue" then
    utils.error "glab doesn't have <fzf_lua_default_issue for issues> implemented"
  elseif kind == "pull_request" then
    query = graphql("pull_request_query", global_id)
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output and vim.api.nvim_buf_is_valid(tmpbuf) then
        local result = vim.fn.json_decode(output)
        local obj
        -- #233 Issues
        if kind == "issue" then
          utils.error "glab doesn't have <fzf_lua_default_issue for issues> implemented"
        elseif kind == "pull_request" then
          obj = result.data.mergeRequest
        end
        writers.write_title(tmpbuf, obj.title, 1)
        -- only a subset of the actual timeline, no need to convert everything
        local converted_pull_request = converters.convert_graphql_pull_request(obj)

        writers.write_details(tmpbuf, converted_pull_request)
        writers.write_body(tmpbuf, converted_pull_request)
        writers.write_state(tmpbuf, converted_pull_request.state:upper(), number)
        local reactions_line = vim.api.nvim_buf_line_count(tmpbuf) - 1
        writers.write_block(tmpbuf, { "", "" }, reactions_line)
        -- #233 Emojis
        --writers.write_reactions(tmpbuf, obj.reactionGroups, reactions_line)
        vim.api.nvim_buf_set_option(tmpbuf, "filetype", "octo")
      end
    end,
  }
end

---@param formatted_pulls table
---@param repo string
---@param order_by OctoConfigOrderBy
---@param filter string
function M.fzf_lua_pull_requests(formatted_pulls, repo, order_by, filter, fzf_cb)
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
        fzf_cb()
      elseif output then
        local prs = vim.fn.json_decode(output)
        local pull_requests, _ = converters.parse_merge_requests_output(prs, repo)
        for _, pull in ipairs(pull_requests) do
          local entry = entry_maker.gen_from_issue(pull)

          if entry ~= nil then
            formatted_pulls[entry.ordinal] = entry
            local prefix = fzf.utils.ansi_from_hl("Comment", entry.obj.number)
            fzf_cb(prefix .. " " .. entry.obj.title)
          end
        end
      end
    end,
  }
end

-- Select a label from the relevant group
---@param buffer OctoBuffer
function M.fzf_lua_select_label(buffer, fzf_cb)
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

        for _, label in ipairs(labels) do
          local colored_name = picker_utils.color_string_with_hex(label.name, label.color)
          fzf_cb(string.format("%s %s", label.id, colored_name))
        end
      end
      fzf_cb()
    end,
  }
end

-- Select one of the labels the issue/pr has assigned (context: remove label from thing)
---@param buffer OctoBuffer
function M.fzf_lua_select_assigned_label(buffer, fzf_cb)
  local query, key
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

        for _, label in ipairs(labels) do
          local colored_name = picker_utils.color_string_with_hex(label.name, label.color)
          fzf_cb(string.format("%s %s", label.id, colored_name))
        end
      end

      fzf_cb()
    end,
  }
end

return M
