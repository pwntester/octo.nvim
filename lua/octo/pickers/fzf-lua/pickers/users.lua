local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

return function(cb)
  local formatted_users = {}

  local function contents(prompt)
    -- skip empty queries
    if not prompt or prompt == "" or utils.is_blank(prompt) then
      return {}
    end
    local query = graphql("users_query", prompt)
    local output = gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      mode = "sync",
    }
    if output then
      local users = {}
      local orgs = {}
      local responses = utils.get_pages(output)
      for _, resp in ipairs(responses) do
        for _, user in ipairs(resp.data.search.nodes) do
          if not user.teams then
            -- regular user
            if not vim.tbl_contains(vim.tbl_keys(users), user.login) then
              users[user.login] = {
                id = user.id,
                login = user.login,
              }
            end
          elseif user.teams and user.teams.totalCount > 0 then
            -- organization, collect all teams
            if not vim.tbl_contains(vim.tbl_keys(orgs), user.login) then
              orgs[user.login] = {
                id = user.id,
                login = user.login,
                teams = user.teams.nodes,
              }
            else
              vim.list_extend(orgs[user.login].teams, user.teams.nodes)
            end
          end
        end
      end

      -- TODO highlight orgs?
      local format_display = function(thing)
        return thing.id .. " " .. thing.login
      end

      local results = {}
      -- process orgs with teams
      for _, user in pairs(users) do
        user.ordinal = format_display(user)
        formatted_users[user.ordinal] = user
        table.insert(results, user.ordinal)
      end
      for _, org in pairs(orgs) do
        org.login = string.format("%s (%d)", org.login, #org.teams)
        org.ordinal = format_display(org)
        formatted_users[org.ordinal] = org
        table.insert(results, org.ordinal)
      end
      return results
    else
      return {}
    end
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
