local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local octo_config = require "octo.config"
local queries = require "octo.gh.queries"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local utils = require "octo.utils"

local M = { orgs = {} }

local delimiter = "\t"

local fzf_opts = {
  ["--delimiter"] = delimiter,
  ["--with-nth"] = "3..",
}

local function format_display(thing, type)
  local str = thing.id .. delimiter .. type .. delimiter .. thing.login
  if thing.name and thing.name ~= vim.NIL then
    str = string.format("%s (%s)", str, thing.name)
  end
  return str
end

local function get_user_requester(prompt)
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
  -- check if the output has }{ and if so, split it and parse each part
  local end_idx = output:find "}{"
  -- add a newline after }{ if it exists
  if end_idx then
    output = output:sub(1, end_idx) .. "\n" .. output:sub(end_idx + 1)
  end
  local jsons = vim.split(output, "\n", { plain = true })
  -- parse each JSON object
  for _, json_raw in ipairs(jsons) do
    local responses = utils.get_pages(json_raw)
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
          -- organization, collect orgs
          if not vim.tbl_contains(vim.tbl_keys(M.orgs), user.login) then
            M.orgs[user.id] = {
              id = user.id,
              login = user.login,
              teams = user.teams.nodes,
            }
          else
            vim.list_extend(M.orgs[user.login].teams, user.teams.nodes)
          end
        end
      end
    end
  end

  local results = {}
  -- process orgs with teams
  for _, user in pairs(users) do
    user.ordinal = format_display(user, "user")
    table.insert(results, user.ordinal)
  end
  for _, org in pairs(M.orgs) do
    org.login = string.format("%s (%d)", org.login, #org.teams)
    org.ordinal = format_display(org, "org")
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
    user.ordinal = format_display(user, "user")
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

local function get_user_id_type(selection)
  local spl = vim.split(selection[1], delimiter)
  return spl[1], spl[2]
end

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
              local user_id, user_type = get_user_id_type(user_selected)
              if user_type == "user" then
                cb(user_id)
              else
                -- handle org
                local formatted_teams = {}
                local team_titles = {}

                for _, team in ipairs(M.orgs[user_id].teams) do
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
                        if false then
                          cb(team_entry.team.id)
                        end
                        utils.error "Not implemented yet"
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
            local user_id, _ = get_user_id_type(user_selected)
            cb(user_id)
          end,
        },
      })
    )
  end
end
