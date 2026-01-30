local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local mutations = require "octo.gh.mutations"
local utils = require "octo.utils"
local vim = vim

local M = {}

---Get project field options for a single-select field
---@param project_id string
---@param field_name string
---@param cb function Callback with field_id and options
local function get_field_options(project_id, field_name, cb)
  local query = string.format(
    [[
query {
  node(id: "%s") {
    ... on ProjectV2 {
      fields(first: 100) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}
]],
    project_id
  )

  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
        return
      end

      local resp = vim.json.decode(output)
      if not resp or not resp.data or not resp.data.node or not resp.data.node.fields then
        utils.error "Failed to fetch project fields"
        return
      end

      for _, field in ipairs(resp.data.node.fields.nodes) do
        if field.name == field_name then
          cb(field.id, field.options)
          return
        end
      end

      utils.error(string.format("Field '%s' not found in project", field_name))
    end,
  }
end

---Update a project field value
---@param opts { project_id: string, item_id: string, field_id: string, option_id: string }
---@param cb function Callback on success
local function update_field_value(opts, cb)
  local query = string.format(mutations.update_project_v2_item, opts.project_id, opts.item_id, opts.field_id, opts.option_id)

  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
        return
      end

      local resp = vim.json.decode(output)
      if resp and resp.data and resp.data.updateProjectV2ItemFieldValue then
        cb()
      else
        utils.error "Failed to update project field"
      end
    end,
  }
end

---Set a project field value (interactive picker)
---@param field_name string The field to set (e.g., "WS")
M.set_field = function(field_name)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]

  if not buffer then
    utils.error "Not in an Octo buffer"
    return
  end

  local issue = buffer:issue()
  if not issue or not issue.projectItems or #issue.projectItems.nodes == 0 then
    utils.error "Issue not in any project"
    return
  end

  -- Use the first project (could be extended to support multiple projects)
  local project_item = issue.projectItems.nodes[1]
  local project_id = project_item.project.id
  local item_id = project_item.id

  get_field_options(project_id, field_name, function(field_id, options)
    if #options == 0 then
      utils.error(string.format("No options found for field '%s'", field_name))
      return
    end

    -- Create picker options
    local items = {}
    for _, option in ipairs(options) do
      table.insert(items, option.name)
    end

    vim.ui.select(items, {
      prompt = string.format("Select %s:", field_name),
    }, function(choice)
      if not choice then
        return
      end

      -- Find the option ID
      local option_id = nil
      for _, option in ipairs(options) do
        if option.name == choice then
          option_id = option.id
          break
        end
      end

      if not option_id then
        utils.error "Invalid selection"
        return
      end

      -- Update the field
      update_field_value({
        project_id = project_id,
        item_id = item_id,
        field_id = field_id,
        option_id = option_id,
      }, function()
        utils.info(string.format("Set %s to '%s'", field_name, choice))
        
        -- Reload the issue to show the updated field
        vim.cmd "edit"
      end)
    end)
  end)
end

return M
