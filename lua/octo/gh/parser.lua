local M = {}

M.projects = function(resp, opts)
  opts = opts or {}
  local sorted = opts.sorted or false

  local projects = {}
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

  local projects_list = vim.tbl_values(projects)

  if not sorted then
    return projects_list
  end

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
