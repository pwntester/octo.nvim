-- debug-info.lua
-- A self-contained script to display GraphQL schema information in a Neovim buffer
--
---@diagnostic disable: no-unknown
local utils = require "octo.utils"
local notify = require "octo.notify"

local M = {}

-- Helper function to safely get nested values
---@param tbl table
---@param ... any
---@return any
local function safe_get(tbl, ...)
  local result = tbl ---@type any
  for _, key in ipairs { ... } do
    if type(result) ~= "table" then
      return vim.NIL
    end
    result = result[key]
    if result == nil then
      return vim.NIL
    end
  end
  return result
end

-- Helper function to check if value is nil/vim.NIL
---@param value any
---@return boolean
local function is_nil(value)
  return value == nil or value == vim.NIL
end

-- Helper function to wrap text at a given width
---@param text string
---@param width number
---@param prefix? string
---@return string[]
local function wrap_text(text, width, prefix)
  prefix = prefix or ""
  local prefix_len = #prefix
  local max_width = width - prefix_len ---@type number
  local wrapped = {} ---@type string[]

  -- First split by existing newlines
  for paragraph in text:gmatch "[^\r\n]+" do
    local line = "" ---@type string
    -- Split paragraph into words
    for word in paragraph:gmatch "%S+" do
      -- Check if adding this word would exceed the width
      local test_line = line == "" and word or (line .. " " .. word) ---@type string
      if #test_line > max_width and line ~= "" then
        -- Add the current line and start a new one
        table.insert(wrapped, prefix .. line)
        line = word
      else
        line = test_line
      end
    end
    -- Add the remaining line
    if line ~= "" then
      table.insert(wrapped, prefix .. line)
    end
  end

  return wrapped
end

-- Helper function to split text by newlines and add to lines table with prefix
---@param lines string[]
---@param text any
---@param prefix? string
---@param wrap_width? number
local function add_text_lines(lines, text, prefix, wrap_width)
  prefix = prefix or ""
  wrap_width = wrap_width or 80

  if is_nil(text) then
    return
  end

  -- Wrap and add lines
  local wrapped = wrap_text(text, wrap_width, prefix)
  for _, line in ipairs(wrapped) do
    table.insert(lines, line)
  end
end

-- Format a type reference (handles SCALAR, OBJECT, ENUM, etc.)
---@param type_info any
---@param depth? number
---@return string
local function format_type(type_info, depth)
  depth = depth or 0
  if depth > 5 then
    return "..."
  end

  if is_nil(type_info) then
    return "nil"
  end

  local kind = type_info.kind ---@type string
  local name = type_info.name ---@type string?
  local ofType = type_info.ofType ---@type any

  if kind == "NON_NULL" then
    return format_type(ofType, depth + 1) .. "!"
  elseif kind == "LIST" then
    return "[" .. format_type(ofType, depth + 1) .. "]"
  elseif not is_nil(name) then
    return name or "Unknown" -- fallback in case name is nil despite check
  else
    return "Unknown"
  end
end

-- Format field arguments
---@param args any
---@return string
local function format_args(args)
  if is_nil(args) or #args == 0 then
    return ""
  end

  local arg_strs = {} ---@type string[]
  for _, arg in ipairs(args) do
    local arg_name = arg.name ---@type string
    local arg_type = format_type(arg.type)
    table.insert(arg_strs, string.format("%s: %s", arg_name, arg_type))
  end

  return "(" .. table.concat(arg_strs, ", ") .. ")"
end

-- Create buffer content for an Interface type
---@param data table
---@return string[]
local function create_interface_buffer_content(data)
  local lines = {} ---@type string[]
  local type_info = safe_get(data, "data", "__type")

  if is_nil(type_info) then
    return { "Error: No __type data found" }
  end

  local kind = safe_get(type_info, "kind")
  local name = safe_get(type_info, "name")
  local description = safe_get(type_info, "description")
  local fields = safe_get(type_info, "fields")
  local possibleTypes = safe_get(type_info, "possibleTypes")

  -- Header
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("%s: %s", kind or "UNKNOWN", name or "Unnamed"))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")

  -- Description
  if not is_nil(description) then
    table.insert(lines, "Description:")
    add_text_lines(lines, description, "  ")
    table.insert(lines, "")
  end

  -- Implemented By (possibleTypes)
  if not is_nil(possibleTypes) and #possibleTypes > 0 then
    table.insert(lines, "Implemented By:")
    for _, possibleType in ipairs(possibleTypes) do
      table.insert(lines, "  - " .. (possibleType.name or "Unknown"))
    end
    table.insert(lines, "")
  end

  -- Fields
  if not is_nil(fields) and #fields > 0 then
    table.insert(lines, "Fields:")
    table.insert(lines, string.rep("-", 80))
    table.insert(lines, "")

    for i, field in ipairs(fields) do
      local field_name = field.name or "unknown"
      local field_type = format_type(field.type)
      local field_args = format_args(field.args)
      local field_desc = field.description ---@type any
      local is_deprecated = field.isDeprecated
      local deprecation_reason = field.deprecationReason

      -- Field signature with deprecation marker
      local signature = string.format("[%d] %s%s: %s", i, field_name, field_args, field_type)
      if is_deprecated then
        signature = signature .. " ⚠ DEPRECATED"
      end
      table.insert(lines, signature)

      -- Field description
      if not is_nil(field_desc) then
        add_text_lines(lines, field_desc, "    ")
      end

      -- Deprecation reason with extra spacing
      if is_deprecated and not is_nil(deprecation_reason) then
        table.insert(lines, "")
        table.insert(lines, "    ⚠ DEPRECATED: " .. deprecation_reason)
      end

      -- Arguments details (if any)
      if not is_nil(field.args) and #field.args > 0 then
        table.insert(lines, "")
        table.insert(lines, "    Arguments:")
        for _, arg in ipairs(field.args) do
          local arg_name = arg.name or "unknown"
          local arg_type = format_type(arg.type)
          local arg_desc = arg.description ---@type any

          table.insert(lines, string.format("      - %s: %s", arg_name, arg_type))
          if not is_nil(arg_desc) then
            add_text_lines(lines, arg_desc, "        ")
          end
        end
      end

      table.insert(lines, "")
    end
  end

  -- Footer
  table.insert(lines, string.rep("=", 80))
  local footer_parts = {}
  if not is_nil(fields) then
    table.insert(footer_parts, string.format("Fields: %d", #fields))
  end
  if not is_nil(possibleTypes) then
    table.insert(footer_parts, string.format("Implementations: %d", #possibleTypes))
  end
  table.insert(lines, table.concat(footer_parts, " | "))
  table.insert(lines, string.rep("=", 80))

  return lines
end

-- Create buffer content for an Object type
---@param data table
---@return string[]
local function create_object_buffer_content(data)
  local lines = {} ---@type string[]
  local type_info = safe_get(data, "data", "__type")

  if is_nil(type_info) then
    return { "Error: No __type data found" }
  end

  local kind = safe_get(type_info, "kind")
  local name = safe_get(type_info, "name")
  local description = safe_get(type_info, "description")
  local fields = safe_get(type_info, "fields")
  local interfaces = safe_get(type_info, "interfaces")

  -- Header
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("%s: %s", kind or "UNKNOWN", name or "Unnamed"))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")

  -- Description
  if not is_nil(description) then
    table.insert(lines, "Description:")
    add_text_lines(lines, description, "  ")
    table.insert(lines, "")
  end

  -- Interfaces
  if not is_nil(interfaces) and #interfaces > 0 then
    table.insert(lines, "Implements:")
    for _, iface in ipairs(interfaces) do
      table.insert(lines, "  - " .. (iface.name or "Unknown"))
    end
    table.insert(lines, "")
  end

  -- Fields
  if not is_nil(fields) and #fields > 0 then
    table.insert(lines, "Fields:")
    table.insert(lines, string.rep("-", 80))
    table.insert(lines, "")

    for i, field in ipairs(fields) do
      local field_name = field.name or "unknown"
      local field_type = format_type(field.type)
      local field_args = format_args(field.args)
      local field_desc = field.description ---@type any
      local is_deprecated = field.isDeprecated
      local deprecation_reason = field.deprecationReason

      -- Field signature with deprecation marker
      local signature = string.format("[%d] %s%s: %s", i, field_name, field_args, field_type)
      if is_deprecated then
        signature = signature .. " ⚠ DEPRECATED"
      end
      table.insert(lines, signature)

      -- Field description
      if not is_nil(field_desc) then
        add_text_lines(lines, field_desc, "    ")
      end

      -- Deprecation reason with extra spacing
      if is_deprecated and not is_nil(deprecation_reason) then
        table.insert(lines, "")
        table.insert(lines, "    ⚠ DEPRECATED: " .. deprecation_reason)
      end

      -- Arguments details (if any)
      if not is_nil(field.args) and #field.args > 0 then
        table.insert(lines, "")
        table.insert(lines, "    Arguments:")
        for _, arg in ipairs(field.args) do
          local arg_name = arg.name or "unknown"
          local arg_type = format_type(arg.type)
          local arg_desc = arg.description ---@type any

          table.insert(lines, string.format("      - %s: %s", arg_name, arg_type))
          if not is_nil(arg_desc) then
            add_text_lines(lines, arg_desc, "        ")
          end
        end
      end

      table.insert(lines, "")
    end
  end

  -- Footer
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("Total Fields: %d", is_nil(fields) and 0 or #fields))
  table.insert(lines, string.rep("=", 80))

  return lines
end

-- Create buffer content for an Input Object type
---@param data table
---@return string[]
local function create_input_object_buffer_content(data)
  local lines = {} ---@type string[]
  local type_info = safe_get(data, "data", "__type")

  if is_nil(type_info) then
    return { "Error: No __type data found" }
  end

  local kind = safe_get(type_info, "kind")
  local name = safe_get(type_info, "name")
  local description = safe_get(type_info, "description")
  local inputFields = safe_get(type_info, "inputFields")

  -- Header
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("%s: %s", kind or "UNKNOWN", name or "Unnamed"))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")

  -- Description
  if not is_nil(description) then
    table.insert(lines, "Description:")
    add_text_lines(lines, description, "  ")
    table.insert(lines, "")
  end

  -- Input Fields
  if not is_nil(inputFields) and #inputFields > 0 then
    table.insert(lines, "Input Fields:")
    table.insert(lines, string.rep("-", 80))
    table.insert(lines, "")

    for i, field in ipairs(inputFields) do
      local field_name = field.name or "unknown"
      local field_type = format_type(field.type)
      local field_desc = field.description ---@type any

      -- Field signature
      table.insert(lines, string.format("[%d] %s: %s", i, field_name, field_type))

      -- Field description
      if not is_nil(field_desc) then
        add_text_lines(lines, field_desc, "    ")
      end

      table.insert(lines, "")
    end
  end

  -- Footer
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("Total Input Fields: %d", is_nil(inputFields) and 0 or #inputFields))
  table.insert(lines, string.rep("=", 80))

  return lines
end

-- Create buffer content for an Enum type
---@param data table
---@return string[]
local function create_enum_buffer_content(data)
  local lines = {} ---@type string[]
  local type_info = safe_get(data, "data", "__type")

  if is_nil(type_info) then
    return { "Error: No __type data found" }
  end

  local kind = safe_get(type_info, "kind")
  local name = safe_get(type_info, "name")
  local description = safe_get(type_info, "description")
  local enumValues = safe_get(type_info, "enumValues")

  -- Header
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("%s: %s", kind or "UNKNOWN", name or "Unnamed"))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")

  -- Description
  if not is_nil(description) then
    table.insert(lines, "Description:")
    add_text_lines(lines, description, "  ")
    table.insert(lines, "")
  end

  -- Enum Values
  if not is_nil(enumValues) and #enumValues > 0 then
    table.insert(lines, "Values:")
    table.insert(lines, string.rep("-", 80))
    table.insert(lines, "")

    for i, enumValue in ipairs(enumValues) do
      local value_name = enumValue.name or "UNKNOWN"
      local value_desc = enumValue.description ---@type any
      local is_deprecated = enumValue.isDeprecated
      local deprecation_reason = enumValue.deprecationReason

      -- Value name with deprecation marker
      local value_line = string.format("[%d] %s", i, value_name)
      if is_deprecated then
        value_line = value_line .. " ⚠ DEPRECATED"
      end
      table.insert(lines, value_line)

      -- Value description
      if not is_nil(value_desc) then
        add_text_lines(lines, value_desc, "    ")
      end

      -- Deprecation reason with extra spacing
      if is_deprecated and not is_nil(deprecation_reason) then
        table.insert(lines, "")
        table.insert(lines, "    ⚠ DEPRECATED: " .. deprecation_reason)
      end

      table.insert(lines, "")
    end
  end

  -- Footer
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("Total Values: %d", is_nil(enumValues) and 0 or #enumValues))
  table.insert(lines, string.rep("=", 80))

  return lines
end

-- Create buffer content for a Union type
---@param data table
---@return string[]
local function create_union_buffer_content(data)
  local lines = {} ---@type string[]
  local type_info = safe_get(data, "data", "__type")

  if is_nil(type_info) then
    return { "Error: No __type data found" }
  end

  local kind = safe_get(type_info, "kind")
  local name = safe_get(type_info, "name")
  local description = safe_get(type_info, "description")
  local possibleTypes = safe_get(type_info, "possibleTypes")

  -- Header
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("%s: %s", kind or "UNKNOWN", name or "Unnamed"))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")

  -- Description
  if not is_nil(description) then
    table.insert(lines, "Description:")
    add_text_lines(lines, description, "  ")
    table.insert(lines, "")
  end

  -- Possible Types
  if not is_nil(possibleTypes) and #possibleTypes > 0 then
    table.insert(lines, "Possible Types:")
    table.insert(lines, string.rep("-", 80))
    table.insert(lines, "")

    for i, possibleType in ipairs(possibleTypes) do
      local type_name = possibleType.name or "Unknown"
      table.insert(lines, string.format("[%d] %s", i, type_name))
    end
    table.insert(lines, "")
  end

  -- Footer
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, string.format("Total Possible Types: %d", is_nil(possibleTypes) and 0 or #possibleTypes))
  table.insert(lines, string.rep("=", 80))

  return lines
end

-- Create and display buffer for any GraphQL type
---@param data table
---@return number bufnr
function M.display_type(data)
  local type_kind = safe_get(data, "data", "__type", "kind")
  local lines ---@type string[]

  if type_kind == "UNION" then
    lines = create_union_buffer_content(data)
  elseif type_kind == "ENUM" then
    lines = create_enum_buffer_content(data)
  elseif type_kind == "INPUT_OBJECT" then
    lines = create_input_object_buffer_content(data)
  elseif type_kind == "INTERFACE" then
    lines = create_interface_buffer_content(data)
  else
    -- Default to object buffer content for OBJECT, SCALAR, and any other types
    lines = create_object_buffer_content(data)
  end

  -- Determine buffer name
  local type_name = safe_get(data, "data", "__type", "name")
  local base_name = type_name and ("GraphQL: " .. type_name) or "GraphQL Schema"

  -- Check if buffer already exists using utility function
  local bufnr = utils.find_named_buffer(base_name)

  -- Create new buffer if it doesn't exist
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, base_name)
  end

  -- Set buffer options
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide" -- Keep buffers hidden (not wiped) for navigation
  vim.bo[bufnr].swapfile = false

  -- Set lines
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Make buffer read-only
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "graphql-schema"

  -- Open buffer in current window using :buffer to ensure jumplist is updated
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= bufnr then
    vim.cmd("buffer " .. bufnr)
  end

  -- Set up syntax highlighting
  vim.cmd [[
    syntax match GraphQLHeader /^=\+$/
    syntax match GraphQLFieldIndex /^\[\d\+\]/
    syntax match GraphQLFieldName /^\[\d\+\] \zs\w\+\ze/
    syntax match GraphQLType /: \zs[A-Z][A-Za-z0-9_\[\]!]\+/
    syntax match GraphQLSection /^Description:\|^Implements:\|^Implemented By:\|^Fields:\|^Input Fields:\|^Arguments:\|^Total Fields:\|^Total Input Fields:\|^Possible Types:\|^Total Possible Types:\|^Values:\|^Total Values:/
    syntax match GraphQLDeprecated /⚠ DEPRECATED/
    syntax match GraphQLDeprecatedReason /^\s*⚠ DEPRECATED:.*$/

    highlight link GraphQLHeader Title
    highlight link GraphQLFieldIndex Number
    highlight link GraphQLFieldName Identifier
    highlight link GraphQLType Type
    highlight link GraphQLSection Keyword
    highlight GraphQLDeprecated ctermfg=Yellow guifg=#E5C07B gui=bold cterm=bold
    highlight GraphQLDeprecatedReason ctermfg=Red guifg=#E06C75 gui=italic cterm=italic
  ]]

  -- Set up buffer-local keymaps, passing the type data
  -- This will overwrite existing keymaps with new closures that capture the current data
  M.setup_buffer_keymaps(bufnr, data)

  return bufnr
end

-- Alias for backward compatibility
M.display_object_type = M.display_type

-- Build GitHub GraphQL documentation URL based on type kind
local function build_graphql_docs_url(type_name, type_kind)
  local base_url = "https://docs.github.com/en/graphql/reference"

  -- Map type kinds to their documentation sections
  local kind_to_section = {
    OBJECT = "objects",
    INTERFACE = "interfaces",
    ENUM = "enums",
    UNION = "unions",
    INPUT_OBJECT = "input-objects",
    SCALAR = "scalars",
  }

  local section = kind_to_section[type_kind] or "objects"
  return string.format("%s/%s#%s", base_url, section, type_name:lower())
end

-- Set up buffer-local keymaps for GraphQL schema buffers
---@param bufnr number
---@param data table The GraphQL type data object
function M.setup_buffer_keymaps(bufnr, data)
  local type_kind = safe_get(data, "data", "__type", "kind")
  local type_name = safe_get(data, "data", "__type", "name")

  -- Map 'gd' to go to definition of type under cursor
  vim.keymap.set("n", "gd", function()
    local debug = require "octo.debug"
    local word = vim.fn.expand "<cword>"

    -- Check if it looks like a GraphQL type (starts with uppercase)
    if word:match "^[A-Z]" then
      vim.cmd "normal! m'" -- Set previous context mark
      debug.lookup(word)
    else
      notify.error("Not a GraphQL type: " .. word)
    end
  end, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Go to GraphQL type definition",
  })

  -- Ensure <C-o> and <C-i> work in these buffers
  vim.keymap.set("n", "<C-o>", "<C-o>", {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Jump to older position",
  })

  vim.keymap.set("n", "<C-i>", "<C-i>", {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Jump to newer position",
  })

  vim.keymap.set("n", "<C-y>", function()
    if not is_nil(type_name) and not is_nil(type_kind) then
      local url = build_graphql_docs_url(type_name, type_kind)
      utils.copy_url(url)
    else
      notify.error "Unable to determine type information for this buffer"
    end
  end, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Copy GraphQL type documentation URL to clipboard",
  })

  -- Map <C-y> to copy GraphQL type documentation URL
  -- Copies the documentation for the current buffer's type, not the word under cursor
  vim.keymap.set("n", "<C-y>", function()
    local navigation = require "octo.navigation"

    if not is_nil(type_name) and not is_nil(type_kind) then
      local url = build_graphql_docs_url(type_name, type_kind)
      utils.copy_url(url)
    else
      notify.error "Unable to determine type information for this buffer"
    end
  end, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Copy GraphQL type documentation URL",
  })

  -- Map <C-b> to open GraphQL type documentation in browser
  -- Opens the documentation for the current buffer's type, not the word under cursor
  vim.keymap.set("n", "<C-b>", function()
    local navigation = require "octo.navigation"

    if not is_nil(type_name) and not is_nil(type_kind) then
      local url = build_graphql_docs_url(type_name, type_kind)
      navigation.open_in_browser_raw(url)
      notify.info("Opening documentation for: " .. type_name)
    else
      notify.error "Unable to determine type information for this buffer"
    end
  end, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    desc = "Open GraphQL type documentation in browser",
  })
end

return M
