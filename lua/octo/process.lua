-- lua/octo/process.lua
local M = {}

---@class OctoResult
---@field code number The exit code
---@field stdout string Combined stdout
---@field stderr string Combined stderr
---@field data string The primary output (stdout or stderr)
---@field json fun(): table Helper to decode JSON
---@field trim fun(): string Helper to trim primary output
---@field ok fun(): boolean Helper to check exit code

---@class OctoRuntimeOpts
---@field stdin? string
---@field env? table<string, string|integer>
---@field timeout? number
---@field cwd? string
---@field stream_cb? fun(stdout: string?, stderr: string?)
---@field cb? fun(stdout: string, stderr: string, code: number, result: OctoResult)
---@field dry_run? boolean

---@class OctoDryRunResult
---@field command string[]
---@field opts vim.SystemOpts
---@field timeout? number
---@field ok fun(): boolean

---@alias OctoProcessResult OctoResult|OctoDryRunResult

---@param text string
---@return table
local function json_decode_or_empty(text)
  local ok, decoded = pcall(vim.json.decode, text)
  return ok and decoded or {}
end

---@param obj vim.SystemCompleted
---@return OctoResult
local function wrap_res(obj)
  local result = {
    code = obj.code,
    stdout = obj.stdout or "",
    stderr = obj.stderr or "",
  }

  result.data = (result.code == 0 and result.stdout ~= "") and result.stdout or result.stderr

  result.json = function()
    return json_decode_or_empty(result.stdout)
  end

  result.trim = function()
    return vim.trim(result.data)
  end

  result.ok = function()
    return result.code == 0
  end

  return result
end

---@param carry string
---@param chunk string
---@param emit fun(line: string): nil
---@return string
local function emit_complete_lines(carry, chunk, emit)
  local buffered = carry .. chunk
  while true do
    local idx = buffered:find("\n", 1, true)
    if not idx then
      break
    end
    emit(buffered:sub(1, idx - 1))
    buffered = buffered:sub(idx + 1)
  end
  return buffered
end

---@param bin string
---@param args string[]
---@param transformer_opts OctoRuntimeOpts
---@return OctoResult|OctoDryRunResult|nil
function M.run(bin, args, transformer_opts)
  transformer_opts = transformer_opts or {}

  local cmd = { bin, unpack(args) }
  local co = coroutine.running()
  local has_async_callbacks = transformer_opts.cb ~= nil or transformer_opts.stream_cb ~= nil

  local sys_opts = {
    text = true,
    stdin = transformer_opts.stdin,
    env = transformer_opts.env,
    cwd = transformer_opts.cwd,
  }

  if transformer_opts.dry_run then
    return {
      command = cmd,
      opts = sys_opts,
      timeout = transformer_opts.timeout,
      ok = function()
        return true
      end,
    }
  end

  if not co and not has_async_callbacks then
    local obj = vim.system(cmd, sys_opts):wait(transformer_opts.timeout)
    return wrap_res(obj)
  end

  local stdout_chunks = {}
  local stderr_chunks = {}
  local stdout_carry = ""
  local stderr_carry = ""

  if transformer_opts.stream_cb then
    sys_opts.stdout = function(_, data)
      if not data then
        return
      end
      table.insert(stdout_chunks, data)
      stdout_carry = emit_complete_lines(stdout_carry, data, function(line)
        transformer_opts.stream_cb(line, nil)
      end)
    end

    sys_opts.stderr = function(_, data)
      if not data then
        return
      end
      table.insert(stderr_chunks, data)
      stderr_carry = emit_complete_lines(stderr_carry, data, function(line)
        transformer_opts.stream_cb(nil, line)
      end)
    end
  end

  vim.system(cmd, sys_opts, function(obj)
    if transformer_opts.stream_cb then
      if stdout_carry ~= "" then
        transformer_opts.stream_cb(stdout_carry, nil)
      end
      if stderr_carry ~= "" then
        transformer_opts.stream_cb(nil, stderr_carry)
      end
    end

    ---@diagnostic disable-next-line: no-unknown
    if transformer_opts.stream_cb then
      obj.stdout = table.concat(stdout_chunks)
      obj.stderr = table.concat(stderr_chunks)
    end

    local wrapped = wrap_res(obj)
    if transformer_opts.cb then
      transformer_opts.cb(wrapped.stdout, wrapped.stderr, wrapped.code, wrapped)
    end

    if co then
      vim.schedule(function()
        coroutine.resume(co, wrapped)
      end)
    end
  end)

  if co then
    ---@diagnostic disable-next-line: await-in-sync
    return coroutine.yield()
  end

  ---@diagnostic disable-next-line: return-type-mismatch
  return nil
end

---@param tbl table<string|integer, any>
---@param target string[]
local function append_formatted(tbl, target)
  for k, v in pairs(tbl) do
    if type(k) == "string" then
      local flag = (#k == 1 and "-" or "--") .. k:gsub("_", "-")
      if type(v) == "table" then
        for _, item in ipairs(v) do
          vim.list_extend(target, { flag, tostring(item) })
        end
      else
        table.insert(target, flag)
        if v ~= true then
          table.insert(target, tostring(v))
        end
      end
    end
  end
  for i = 1, math.huge do
    if tbl[i] == nil then
      break
    end
    table.insert(target, tostring(tbl[i]))
  end
end

---The "Standard" Transformer logic
---Handles: { flag = true } -> --flag, { f = "val" } -> -f val, { list = {1, 2} } -> --list 1 --list 2
---Reserved keys stripped from CLI output: opts, _stdin, args
---When args is present, a `--` separator is inserted before its contents
---@param path string[]
---@param opts table<string|integer, any>
---@return string[], OctoRuntimeOpts
function M.default_transformer(path, opts)
  opts = vim.deepcopy(opts or {})

  local args = vim.deepcopy(path)
  ---@type table
  local runtime_opts = type(opts.opts) == "table" and opts.opts or {}

  if opts._stdin ~= nil and runtime_opts.stdin == nil then
    runtime_opts.stdin = opts._stdin
  end

  opts._stdin = nil
  opts.opts = nil

  ---@type table?
  local extra_args = opts.args
  opts.args = nil

  -- Strip any literal "--" from args since we auto-insert it below
  if extra_args ~= nil then
    ---@type table
    local cleaned = {}
    local pos = 1
    for i = 1, math.huge do
      if extra_args[i] == nil then
        break
      end
      if extra_args[i] ~= "--" then
        cleaned[pos] = extra_args[i]
        pos = pos + 1
      end
    end
    for k, v in pairs(extra_args) do
      if type(k) == "string" then
        cleaned[k] = v
      end
    end
    extra_args = cleaned
  end

  ---@type OctoRuntimeOpts
  local t_opts = {
    stdin = runtime_opts.stdin,
    env = runtime_opts.env,
    timeout = runtime_opts.timeout,
    cwd = runtime_opts.cwd,
    stream_cb = runtime_opts.stream_cb,
    cb = runtime_opts.cb,
    dry_run = runtime_opts.dry_run,
  }

  append_formatted(opts, args)

  if extra_args ~= nil and next(extra_args) ~= nil then
    table.insert(args, "--")
    append_formatted(extra_args, args)
  end

  return args, t_opts
end

---The Proxy Factory
---@param bin string
---@param transformer? fun(path: string[], opts: table): string[], OctoRuntimeOpts
---@return table
function M.factory(bin, transformer)
  transformer = transformer or M.default_transformer

  local function make_proxy(path)
    return setmetatable({}, {
      __index = function(_, key)
        ---@diagnostic disable-next-line: no-unknown
        local segment = key:gsub("_", "-")
        return make_proxy(vim.list_extend(vim.deepcopy(path), { segment }))
      end,
      __call = function(_, opts)
        opts = opts or {}
        ---@type string[], OctoRuntimeOpts
        local args, t_opts = transformer(path, opts)
        ---@type OctoResult|OctoDryRunResult
        return M.run(bin, args, t_opts)
      end,
    })
  end
  return make_proxy {}
end

return M
