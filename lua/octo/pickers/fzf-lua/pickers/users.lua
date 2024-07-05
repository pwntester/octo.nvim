local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(cb)
  local formatted_users = {}

  local function contents(prompt)
    -- skip empty queries
    if not prompt or prompt == "" or utils.is_blank(prompt) then
      return {}
    end
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_get_users"]
    func(formatted_users, prompt)
  end

  fzf.fzf_live(
    contents,
    vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
      fzf_opts = {
        ["--delimiter"] = "' '",
        ["--with-nth"] = "2..",
      },
      actions = {
        ["default"] = {
          function(user_selected)
            local user_entry = formatted_users[user_selected[1]]
            if not user_entry.teams then
              -- user
              cb(user_entry.id)
            else
              local formatted_teams = {}
              local team_titles = {}

              for _, team in ipairs(user_entry.teams) do
                local team_entry = entry_maker.gen_from_team(team)

                if team_entry ~= nil then
                  formatted_teams[team_entry.ordinal] = team_entry
                  table.insert(team_titles, team_entry.ordinal)
                end
              end

              fzf.fzf_exec(
                team_titles,
                vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
                  actions = {
                    ["default"] = function(team_selected)
                      local team_entry = formatted_teams[team_selected[1]]
                      cb(team_entry.team.id)
                    end,
                  },
                })
              )
            end
          end,
        },
      },
    })
  )
end
