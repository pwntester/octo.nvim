local M = {}

---@class octo.Project
---@field id string
---@field title string
---@field url string
---@field closed boolean
---@field number number
---@field owner { login: string }
---@field columns { id: string, options: { id: string, name: string }[] }?

--- Parse projects from a GraphQL response.
--- @param resp table The GraphQL response.
--- @param opts { sorted: boolean }? Options for parsing.
--- @return octo.Project[] List of parsed projects.
M.projects = function(resp, opts)
  opts = opts or {}
  local sorted = opts.sorted or false

  ---@type table<string, octo.Project>
  local projects = {}
  ---@type octo.Project[][]
  local sources = {
    resp.data.user and resp.data.user.projects.nodes or {},
    resp.data.repository and resp.data.repository.projects.nodes or {},
    not resp.errors and resp.data.organization.projects.nodes or {},
  }

  -- Consolidate all projects into a map keyed by ID to remove duplicates
  for _, source in ipairs(sources) do
    for _, project in ipairs(source) do
      projects[project.id] = project
    end
  end

  ---@type octo.Project[]
  local projects_list = vim.tbl_values(projects)

  if not sorted then
    return projects_list
  end

  ---@type octo.Project[]
  local sorted_projects = {}
  for _, project in ipairs(projects_list) do
    if project.closed then
      table.insert(sorted_projects, project)
    else
      table.insert(sorted_projects, 1, project)
    end
  end

  return sorted_projects
end

return M
