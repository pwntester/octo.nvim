local queries = require "octo.gh.queries"
local mutations = require "octo.gh.mutations"

---@param query string
---@param ... string|table
---@return string
return function(query, ...)
  local suffix, module
  if vim.endswith(query, "_mutation") then
    module = mutations
    suffix = "_mutation"
  else
    module = queries
    suffix = "_query"
  end

  query = query:gsub(suffix, "")

  local opts = { escape = true }
  for _, v in ipairs { ... } do
    if type(v) == "table" then
      opts = vim.tbl_deep_extend("force", opts, v)
      break
    end
  end
  local args = {}
  for _, v in ipairs { ... } do
    table.insert(args, v)
  end
  return string.format(module[query], unpack(args))
end
