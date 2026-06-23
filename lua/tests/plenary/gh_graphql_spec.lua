local queries = require "octo.gh.queries"
local mutations = require "octo.gh.mutations"

if type(queries.pending_review_threads) ~= "string" then
  local config = require "octo.config"
  local fragments = require "octo.gh.fragments"
  config.setup {}
  fragments.setup()
  queries.setup()
  mutations.setup()
end

local function extract_fragment_names(gql)
  local names = {}
  for name in gql:gmatch "fragment%s+(%w+)%s+on" do
    names[#names + 1] = name
  end
  return names
end

describe("GraphQL queries", function()
  for name, query in pairs(queries) do
    if type(query) == "string" then
      it(name .. " has no duplicate fragment definitions", function()
        local names = extract_fragment_names(query)
        local seen = {}
        for _, fragment_name in ipairs(names) do
          if seen[fragment_name] then
            error("Duplicate fragment '" .. fragment_name .. "' in query " .. name, 0)
          end
          seen[fragment_name] = true
        end
      end)
    end
  end
end)

describe("GraphQL mutations", function()
  for name, mutation in pairs(mutations) do
    if type(mutation) == "string" then
      it(name .. " has no duplicate fragment definitions", function()
        local names = extract_fragment_names(mutation)
        local seen = {}
        for _, fragment_name in ipairs(names) do
          if seen[fragment_name] then
            error("Duplicate fragment '" .. fragment_name .. "' in mutation " .. name, 0)
          end
          seen[fragment_name] = true
        end
      end)
    end
  end
end)
