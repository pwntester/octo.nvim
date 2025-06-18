local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local octo_config = require "octo.config"
local queries = require "octo.gh.queries"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

local M = { formatted_users = {} }

local delimiter = "\t"

local fzf_opts = {
  ["--delimiter"] = delimiter,
  ["--with-nth"] = "2..",
}

local function format_display(thing)
  local str = thing.id .. delimiter .. thing.login
  if thing.name and thing.name ~= vim.NIL then
    str = string.format("%s (%s)", str, thing.name)
  end
  return str
end

local function get_user_requester(prompt)
  M.formatted_users = {} -- reset formatted users
  -- skip empty queries
  if not prompt or prompt == "" or utils.is_blank(prompt) then
    return {}
  end
  local query = graphql("users_query", prompt)
  local output = gh.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if not output then
    return {}
  end
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
          if user.name then
            users[user.login].name = user.name
          end
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

  local results = {}
  -- process orgs with teams
  for _, user in pairs(users) do
    user.ordinal = format_display(user)
    M.formatted_users[user.ordinal] = user
    table.insert(results, user.ordinal)
  end
  for _, org in pairs(orgs) do
    org.login = string.format("%s (%d)", org.login, #org.teams)
    org.ordinal = format_display(org)
    M.formatted_users[org.ordinal] = org
    table.insert(results, org.ordinal)
  end
  return results
end

local function get_users(query_name, node_name)
  local repo = utils.get_remote_name()
  local owner, name = utils.split_repo(repo)
  local output = gh.api.graphql {
    query = queries[query_name],
    f = { owner = owner, name = name },
    paginate = true,
    jq = ".data.repository." .. node_name .. ".nodes",
    opts = { mode = "sync" },
  }
  if utils.is_blank(output) then
    return {}
  end

  local results = {}
  local flattened = utils.get_flatten_pages(output)
  for _, user in ipairs(flattened) do
    user.ordinal = format_display(user)
    table.insert(results, user.ordinal)
  end
  return results
end

local function get_assignable_users()
  return get_users("assignable_users", "assignableUsers")
end

local function get_mentionable_users()
  return get_users("mentionable_users", "mentionableUsers")
end

-- return M

return function(cb)
  local cfg = octo_config.values
  if cfg.users == "search" then
    return fzf.fzf_live(
      get_user_requester,
      vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
        fzf_opts = fzf_opts,
        actions = {
          ["default"] = {
            function(user_selected)
              local user_entry = M.formatted_users[user_selected[1]]
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
  else
    local users = {}
    if cfg.users == "assignable" then
      users = get_assignable_users()
    elseif cfg.users == "mentionable" then
      users = get_mentionable_users()
    else
      utils.error("Invalid user selection mode: " .. cfg.users)
      return
    end
    if #users == 0 then
      utils.error(string.format("No %s users found.", cfg.users))
      return
    end
    fzf.fzf_exec(
      users,
      vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
        fzf_opts = fzf_opts,
        actions = {
          ["default"] = function(user_selected)
            local user_id = vim.split(user_selected[1], delimiter)[1]
            cb(user_id)
          end,
        },
      })
    )
  end
end
