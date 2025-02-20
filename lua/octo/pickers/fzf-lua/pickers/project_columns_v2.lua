local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"

return function(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local formatted_projects = {} ---@type table<string, table> entry.ordinal -> entry
  local common_fzf_opts = vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
    fzf_opts = {
      ["--delimiter"] = "' '",
      ["--with-nth"] = "2..",
    },
  })

  local get_projects = function(fzf_cb)
    local query = graphql("projects_query_v2", buffer.owner, buffer.name, vim.g.octo_viewer, buffer.owner)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output)
        if output then
          local resp = vim.json.decode(output)

          local unsorted_projects = {}
          local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
          local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
          local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
          vim.list_extend(unsorted_projects, repo_projects)
          vim.list_extend(unsorted_projects, user_projects)
          vim.list_extend(unsorted_projects, org_projects)

          local projects = {}
          for _, project in ipairs(unsorted_projects) do
            if project.closed then
              table.insert(projects, #projects + 1, project)
            else
              table.insert(projects, 0, project)
            end
          end

          if #projects == 0 then
            utils.error(string.format("There are no matching projects for %s.", buffer.repo))
            fzf_cb()
          end

          for _, project in ipairs(projects) do
            local entry = entry_maker.gen_from_project_v2(project)

            if entry ~= nil then
              formatted_projects[entry.ordinal] = entry
              fzf_cb(entry.ordinal)
            end
          end
        end

        fzf_cb()
      end,
    }
  end

  local default_action = function(selected_project)
    local entry_project = formatted_projects[selected_project[1]]

    local formatted_project_columns = {}
    local project_column_titles = {}

    for _, project_column in ipairs(entry_project.obj.columns.options) do
      local entry_column = entry_maker.gen_from_project_v2_column(project_column)

      if entry_column ~= nil then
        formatted_project_columns[entry_column.ordinal] = entry_column
        table.insert(project_column_titles, entry_column.ordinal)
      end
    end

    fzf.fzf_exec(
      project_column_titles,
      vim.tbl_deep_extend("force", common_fzf_opts, {
        actions = {
          ["default"] = function(selected_column)
            local entry_column = formatted_project_columns[selected_column[1]]
            cb(entry_project.id, entry_project.obj.columns.id, entry_column.value)
          end,
        },
      })
    )
  end

  fzf.fzf_exec(
    get_projects,
    vim.tbl_deep_extend("force", common_fzf_opts, {
      actions = vim.tbl_deep_extend("force", fzf_actions.common_open_actions(formatted_projects), {
        ["default"] = {
          default_action,
        },
      }),
    })
  )
end
