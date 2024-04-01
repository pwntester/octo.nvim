local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"

return function(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local formatted_projects = {}
  local common_fzf_opts = vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
    fzf_opts = {
      ["--delimiter"] = "' '",
      ["--with-nth"] = "2..",
    },
  })

  local get_projects = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_select_target_project_column"]
    func(formatted_projects, buffer, fzf_cb)
  end

  local default_action = function(selected_project)
    local entry_project = formatted_projects[selected_project[1]]

    local formatted_project_columns = {}
    local project_column_titles = {}

    for _, project_column in ipairs(entry_project.project.columns.nodes) do
      local entry_column = entry_maker.gen_from_project_column(project_column)

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
            cb(entry_column.column.id)
          end,
        },
      })
    )
  end

  fzf.fzf_exec(
    get_projects,
    vim.tbl_deep_extend("force", common_fzf_opts, {
      actions = {
        ["default"] = {
          default_action,
        },
      },
    })
  )
end
