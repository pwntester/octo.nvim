---@diagnostic disable
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
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
    local output, stderr = gh.api.graphql {
      query = queries.users,
      F = { prompt = prompt },
      paginate = true,
      opts = { mode = "sync" },
    }
    local responses, err = utils.get_graphql_pages(output, stderr)
    if err then
      utils.error(err)
    end
    if responses then
      local users = {}
      local orgs = {}
      for _, resp in ipairs(responses) do
        local nodes = resp.data.search and resp.data.search.nodes or {}
        for _, user in ipairs(nodes) do
          -- Orgs hidden due to missing 2FA are returned as "null"
          if type(user) == "table" then
            if not user.teams then
              -- regular user
              if not vim.tbl_contains(vim.tbl_keys(users), user.login) then
                users[user.login] = {
                  id = user.id,
                  login = user.login,
                }
              end
            elseif user.teams.totalCount > 0 then
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
      end

      -- TODO highlight orgs?
      local function format_display(thing)
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
      -- Every keystroke runs a GitHub user search. Debounce the reload to keep
      -- typing below the search rate limit.
      query_delay = 250,
      fzf_opts = {
        ["--delimiter"] = " ",
        ["--with-nth"] = "2..",
      },
      actions = {
        ["default"] = {
          function(user_selected)
            local user_entry = formatted_users[user_selected[1]]
            if not user_entry then
              return
            end
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
                      if not team_entry then
                        return
                      end
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
