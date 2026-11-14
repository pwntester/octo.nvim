local queries = require "octo.gh.queries"

---Format a stored query with its arguments, e.g. graphql("issue_query", owner, name, id).
---The trailing `_query` suffix in the name is optional.
---@param query string
---@param ... string|table
---@return string
return function(query, ...)
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
  local name = (query:gsub("_query$", ""))
  return string.format(queries[name], unpack(args))
end
