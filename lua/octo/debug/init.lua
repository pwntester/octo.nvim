---Helper functions for debugging Octo internals
local utils = require "octo.utils"
local context = require "octo.context"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local graphql_buffer = require "octo.debug.buffer"

local M = {}

---Get the current Octo buffer information
function M.current_buffer()
  context.within_octo_buffer(function(buffer)
    utils.info(vim.inspect(buffer))
  end)()
end

---Get the current Octo context information
function M.globals()
  utils.info(vim.inspect {
    octo_buffers = _G.octo_buffers,
    octo_repo_issues = _G.octo_repo_issues,
    octo_pv2_fragment = _G.octo_pv2_fragment,
    OctoLastCmdOpts = _G.OctoLastCmdOpts,
  })
end

function M.list_types(cb)
  cb = cb or function(data)
    utils.info(vim.inspect(data))
  end
  gh.api.graphql {
    query = queries.introspective_types,
    jq = ".data.__schema.types | map({name, description})",
    opts = {
      cb = gh.create_callback {
        success = function(data)
          local decoded = vim.json.decode(data)
          vim.ui.select(decoded, {
            prompt = "Select a GraphQL type:",
            format_item = function(item)
              return item.name .. (not utils.is_blank(item.description) and (" - " .. item.description) or "")
            end,
          }, function(choice)
            if choice then
              cb(choice)
            else
              utils.info "No type selected"
            end
          end)
        end,
      },
    },
  }
end

---Lookup a GraphQL type by name
---@param name? string
function M.lookup(name, cb)
  cb = cb or function(data)
    local decoded = vim.json.decode(data)
    graphql_buffer.display_type(decoded)
  end
  local function callback(n)
    gh.api.graphql {
      query = queries.introspective_type,
      F = { name = n },
      opts = {
        cb = gh.create_callback { success = cb },
      },
    }
  end

  if name then
    callback(name)
    return
  end

  M.list_types(function(type)
    callback(type.name)
  end)
end

return M
