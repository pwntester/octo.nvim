local uv = vim.uv
local iter = vim.iter

--- Coroutine friendly libuv wrappers, coroutines utils and vim.schedule util
local auv = {}

---@param co thread
---@param ... any
function auv.co_resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    vim.notify(debug.traceback(co, err), vim.log.levels.ERROR)
  end
end

---@async
function auv.schedule()
  local co = coroutine.running()
  vim.schedule(function()
    auv.co_resume(co)
  end)
  coroutine.yield()
end

---@async
---@param path string
---@param flags string|integer
---@param mode integer
---@return nil|string err, integer|nil fd
function auv.fs_open(path, flags, mode)
  local co = coroutine.running()
  uv.fs_open(path, flags, mode, function(err, fd)
    auv.co_resume(co, err, fd)
  end)
  return coroutine.yield()
end

---@async
---@param fd integer
---@param size integer
---@param offset integer|nil
---@return nil|string err, string|nil data
function auv.fs_read(fd, size, offset)
  local co = coroutine.running()
  uv.fs_read(fd, size, offset, function(err, data)
    auv.co_resume(co, err, data)
  end)
  return coroutine.yield()
end

---@async
---@param path string
---@return nil|string err, table|nil stat
function auv.fs_stat(path)
  local co = coroutine.running()
  uv.fs_stat(path, function(err, stat)
    auv.co_resume(co, err, stat)
  end)
  return coroutine.yield()
end

---@async
---@param fd integer
---@return nil|string err, table|nil stat
function auv.fs_fstat(fd)
  local co = coroutine.running()
  uv.fs_fstat(fd, function(err, stat)
    auv.co_resume(co, err, stat)
  end)
  return coroutine.yield()
end

---@async
---@param fd integer
---@return nil|string err, boolean|nil success
function auv.fs_close(fd)
  local co = coroutine.running()
  uv.fs_close(fd, function(err, success)
    auv.co_resume(co, err, success)
  end)
  return coroutine.yield()
end

---@async
---@param fd integer
---@param data string
---@param offset integer|nil
---@return nil|string err, integer|nil bytes
function auv.fs_write(fd, data, offset)
  local co = coroutine.running()
  uv.fs_write(fd, data, offset, function(err, bytes)
    auv.co_resume(co, err, bytes)
  end)
  return coroutine.yield()
end

---@alias TypeKind "SCALAR" | "OBJECT" | "UNION" | "INTERFACE" | "INPUT_OBJECT" | "LIST" | "NON_NULL"

---@class Schema
---@field description string?
---@field types Type[]
---@field queryType Type
---@field mutationType Type?
---@field subscriptionType Type?
---@field directives Directive[]

---@class Type
---@field kind TypeKind
---@field name string?
---@field description string?
---@field fields Field[]
---@field interfaces Type[]
---@field possibleTypes Type[]
---@field enumValues EnumValue[]
---@field inputFields InputValue[]
---@field ofType Type?
---@field specifiedByURL string?

---@class Field
---@field name string
---@field description string?
---@field args InputValue[]
---@field type Type
---@field isDeprecated boolean
---@field deprecationReason string?

---@class InputValue
---@field name string
---@field description string?
---@field type Type
---@field defaultValue string?
---@field isDeprecated boolean
---@field deprecationReason string?

---@class EnumValue?
---@field name string
---@field description string?
---@field isDeprecated boolean
---@field deprecationReason string?

---@class Directive?
---@field name string
---@field description string?
---@field locations DirectiveLocation[]
---@field args InputValue[]
---@field isRepeatable boolean

---@alias DirectiveLocation
--- | "QUERY"
--- | "MUTATION"
--- | "SUBSCRIPTION"
--- | "FIELD"
--- | "FRAGMENT_DEFINITION"
--- | "FRAGMENT_SPREAD"
--- | "INLINE_FRAGMENT"
--- | "VARIABLE_DEFINITION"
--- | "SCHEMA"
--- | "SCALAR"
--- | "OBJECT"
--- | "FIELD_DEFINITION"
--- | "ARGUMENT_DEFINITION"
--- | "INTERFACE"
--- | "UNION"
--- | "ENUM"
--- | "ENUM_VALUE"
--- | "INPUT_OBJECT"
--- | "INPUT_FIELD_DEFINITION"

---@param name string
---@return string
local function parse_class_name(name)
  return ("octo.gh.%s"):format(name)
end

local scalar = {
  Int = "integer",
  Float = "number",
  String = "string",
  Boolean = "boolean",
  ID = "string",

  -- Github custom scalars
  Base64String = "string",
  BigInt = "string",
  Date = "string",
  DateTime = "string",
  GitObjectID = "string",
  GitRefname = "string",
  GitSSHRemote = "string",
  GitTimestamp = "string",
  HTML = "string",
  PreciseDateTime = "string",
  URI = "string",
  X509Certificate = "string",
}

---@param type_ Type
---@return string
local function parse_field_type(type_)
  local types = {} ---@type Type[]

  local current = type_
  while current and current ~= vim.NIL do
    table.insert(types, current)
    current = current.ofType
  end

  local name = types[#types].name ---@type string
  local out = {}

  local is_scalar = iter(types):any(function(type_)
    return type_.kind == "SCALAR"
  end)
  local is_list = iter(types):any(function(type_)
    return type_.kind == "LIST"
  end)
  if is_scalar then
    table.insert(out, scalar[name])
  elseif is_list then
    table.insert(out, parse_class_name(name))
    table.insert(out, "[]")
  else
    table.insert(out, parse_class_name(name))
  end

  local is_optional = iter(types):all(function(type)
    return type.kind ~= "NON_NULL"
  end)
  if is_optional and not is_list then
    table.insert(out, " | vim.NIL")
  end

  return table.concat(out, "")
end

coroutine.wrap(function()
  local co = coroutine.running()
  vim.system({ "gh", "api", "graphql" }, nil, function(out)
    auv.co_resume(co, out)
  end)
  local response = coroutine.yield() ---@type vim.SystemCompleted

  if response.stderr ~= "" then
    return vim.notify(response.stderr, vim.log.level.ERROR)
  end

  local ok, schema = pcall(vim.json.decode, response.stdout) ---@type boolean, string
  if not ok then
    return vim.notify(schema, vim.log.level.ERROR)
  end
  ---@cast schema -string
  ---@cast schema +{data: {__schema: Schema}}

  local types = schema.data.__schema.types
  local lines = {
    "---@meta _",
    "",
    "--This file is generated",
    "--DO NOT EDIT",
    "error('Cannot require a meta file')",
  } ---@type string[]

  iter(types)
    :filter(
      ---@param type_ Type
      function(type_)
        return not vim.startswith(type_.name, "__")
          and type_.kind ~= "SCALAR"
          and type_.kind ~= "ENUM"
          and type_.kind ~= "UNION"
          and type_.kind ~= "INTERFACE"
      end
    )
    :each(
      ---@param type_ Type
      function(type_)
        table.insert(lines, "")

        local description = (type_.description ~= vim.NIL and type_.description or ""):gsub("\n", " ")
        local class = ("---@class %s %s"):format(parse_class_name(type_.name), description)
        table.insert(lines, class)

        local class_fields = type_.fields ~= vim.NIL and type_.fields or type_.inputFields
        if class_fields == vim.NIL then
          return
        end
        local fields = iter(class_fields)
          :map(
            ---@param field Field
            function(field)
              local field_type = parse_field_type(field.type)
              local field_description = (field.description ~= vim.NIL and field.description or ""):gsub("\n", " ")
              local field_name = field.name
              -- https://luals.github.io/wiki/annotations/#field
              if
                field_name == "public"
                or field_name == "private"
                or field_name == "protected"
                or field_name == "package"
              then
                field_name = ('["%s"]'):format(field_name)
              end
              return ("---@field %s %s %s"):format(field_name, field_type, field_description or "")
            end
          )
          :totable()
        vim.list_extend(lines, fields)
      end
    )
  iter(types)
    :filter(
      ---@param type_ Type
      function(type_)
        return not vim.startswith(type_.name, "__") and type_.kind == "ENUM"
      end
    )
    :each(
      ---@param type_ Type
      function(type_)
        table.insert(lines, "")

        local description = (type_.description ~= vim.NIL and type_.description or ""):gsub("\n", " ")
        table.insert(lines, ("---%s"):format(description))
        local class = ("---@alias %s"):format(parse_class_name(type_.name))
        table.insert(lines, class)

        local class_e_values = type_.enumValues ~= vim.NIL and type_.enumValues or nil
        if not class_e_values then
          return
        end
        local fields = iter(class_e_values)
          :map(
            ---@param e_value EnumValue
            function(e_value)
              local e_name = e_value.name
              local e_description = (e_value.description or ""):gsub("\n", " ")
              return ('---| "%s" %s'):format(e_name, e_description)
            end
          )
          :totable()
        vim.list_extend(lines, fields)
      end
    )
  iter(types)
    :filter(
      ---@param type_ Type
      function(type_)
        return not vim.startswith(type_.name, "__") and (type_.kind == "UNION" or type_.kind == "INTERFACE")
      end
    )
    :each(
      ---@param type_ Type
      function(type_)
        table.insert(lines, "")

        local description = (type_.description ~= vim.NIL and type_.description or ""):gsub("\n", " ")
        table.insert(lines, ("---%s"):format(description))
        local class = ("---@alias %s"):format(parse_class_name(type_.name))
        table.insert(lines, class)

        if not type_.possibleTypes or type_.possibleTypes == vim.NIL then
          return
        end

        local possible_types = iter(type_.possibleTypes)
          :map(
            ---@param type_ Type
            function(type_)
              local type_name = parse_class_name(type_.name)
              return ("---| %s"):format(type_name)
            end
          )
          :totable()
        vim.list_extend(lines, possible_types)
      end
    )

  local err4, out_file = auv.fs_open("./lua/octo/_meta/gh.lua", "w", 292) --- 444
  if err4 then
    return vim.notify(err4, vim.log.level.ERROR)
  end
  ---@cast out_file -nil

  local err5 = auv.fs_write(out_file, table.concat(lines, "\n"))
  if err5 then
    return vim.notify(err5, vim.log.level.ERROR)
  end

  local err6 = auv.fs_close(out_file)
  if err6 then
    return vim.notify(err6, vim.log.level.ERROR)
  end
end)()
