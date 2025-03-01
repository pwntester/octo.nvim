local config = require "octo.config"
local fragments = require "octo.gh.fragments"
local _, Job = pcall(require, "plenary.job")
local vim = vim

local M = {}

local headers = {
  "application/vnd.github.v3+json",
  "application/vnd.github.squirrel-girl-preview+json",
  "application/vnd.github.comfort-fade-preview+json",
  "application/vnd.github.bane-preview+json",
}

local env_vars = {
  PATH = vim.env["PATH"],
  GH_CONFIG_DIR = vim.env["GH_CONFIG_DIR"],
  GITHUB_TOKEN = vim.env["GITHUB_TOKEN"],
  XDG_CONFIG_HOME = vim.env["XDG_CONFIG_HOME"],
  XDG_DATA_HOME = vim.env["XDG_DATA_HOME"],
  XDG_STATE_HOME = vim.env["XDG_STATE_HOME"],
  AppData = vim.env["AppData"],
  LocalAppData = vim.env["LocalAppData"],
  HOME = vim.env["HOME"],
  NO_COLOR = 1,
  http_proxy = vim.env["http_proxy"],
  https_proxy = vim.env["https_proxy"],
  no_proxy = vim.env["no_proxy"],
  SSH_AUTH_SOCK = vim.env["SSH_AUTH_SOCK"],
}

local function get_env()
  local env = env_vars
  local gh_env = config.values.gh_env
  if type(gh_env) == "function" then
    local computed_env = gh_env()
    if type(computed_env) == "table" then
      env = vim.tbl_deep_extend("force", env, computed_env)
    end
  elseif type(gh_env) == "table" then
    env = vim.tbl_deep_extend("force", env, gh_env)
  end

  return env
end

-- uses GH to get the name of the authenticated user
function M.get_user_name(remote_hostname)
  if remote_hostname == nil then
    remote_hostname = require("octo.utils").get_remote_host()
  end

  local job = Job:new {
    enable_recording = true,
    command = config.values.gh_cmd,
    args = { "auth", "status", "--hostname", remote_hostname },
    env = get_env(),
  }
  job:sync()
  local stderr = table.concat(job:stderr_result(), "\n")
  local stdout = table.concat(job:result(), "\n")
  -- Newer versions of the gh cli have a different message. See #467
  local name_err = string.match(stderr, "Logged in to [^%s]+ as ([^%s]+)")
    or string.match(stderr, "Logged in to [^%s]+ account ([^%s]+)")
  local name_out = string.match(stdout, "Logged in to [^%s]+ as ([^%s]+)")
    or string.match(stdout, "Logged in to [^%s]+ account ([^%s]+)")

  if name_err then
    return name_err
  elseif name_out then
    return name_out
  else
    require("octo.utils").error(stderr)
  end
end

local scopes = {}

function M.has_scope(test_scopes)
  for _, test_scope in ipairs(test_scopes) do
    if vim.tbl_contains(scopes, test_scope) then
      return true
    end
  end

  return false
end

function M.setup()
  _G.octo_pv2_fragment = ""
  Job:new({
    enable_recording = true,
    command = config.values.gh_cmd,
    args = { "auth", "status" },
    env = get_env(),
    on_exit = vim.schedule_wrap(function(j_self, _, _)
      local use_proj_v2 = config.values.default_to_projects_v2
      local stdout = table.concat(j_self:result(), "\n")
      local all_scopes = string.match(stdout, " Token scopes: (.*)") or ""
      local split = vim.split(all_scopes, ", ")
      for idx, split_scope in ipairs(split) do
        scopes[idx] = string.gsub(split_scope, "'", "")
      end
      if use_proj_v2 then
        if M.has_scope { "read:project", "project" } then
          _G.octo_pv2_fragment = fragments.projects_v2
        elseif not config.values.suppress_missing_scope.projects_v2 then
          require("octo.utils").error "Cannot request Projects v2: Missing scope 'read:project' or 'project'"
        end
      end
    end),
  }):start()
end

--- Create a callback function for the job
function M.create_callback(opts)
  opts = opts or {}

  local utils = require "octo.utils"

  opts.success = opts.success or utils.info
  opts.failure = opts.failure or utils.error

  return function(output, stderr)
    if stderr and not utils.is_blank(stderr) then
      opts.failure(stderr)
    elseif output then
      opts.success(output)
    end
  end
end

---@class RunOpts
---@field args table
---@field mode string
---@field cb fun(stdout: string, stderr: string)
---@field stream_cb fun(stdout: string, stderr: string)
---@field headers table
---@field hostname string

---Run a gh command
---@param opts RunOpts
---@return string[]|nil
local function run(opts)
  if not Job then
    return
  end
  local remote_hostname = require("octo.utils").get_remote_host()

  -- Lazy load viewer name on the first gh command
  if not vim.g.octo_viewer then
    vim.g.octo_viewer = M.get_user_name(remote_hostname)
  end

  opts = opts or {}
  local conf = config.values
  local mode = opts.mode or "async"
  local hostname = ""
  if opts.args[1] == "api" then
    table.insert(opts.args, "-H")
    table.insert(opts.args, "Accept: " .. table.concat(headers, ";"))
    if not require("octo.utils").is_blank(opts.hostname) then
      hostname = opts.hostname
    elseif not require("octo.utils").is_blank(conf.github_hostname) then
      hostname = conf.github_hostname
    elseif not require("octo.utils").is_blank(remote_hostname) then
      hostname = remote_hostname
    end
    if not require("octo.utils").is_blank(hostname) and hostname ~= "github.com" then
      table.insert(opts.args, "--hostname")
      table.insert(opts.args, hostname)
    end
  end
  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(opts.args, "-H")
      table.insert(opts.args, header)
    end
  end

  local job = Job:new {
    enable_recording = true,
    command = config.values.gh_cmd,
    args = opts.args,
    on_stdout = vim.schedule_wrap(function(err, data, _)
      if mode == "async" and opts.stream_cb then
        opts.stream_cb(data, err)
      end
    end),
    on_exit = vim.schedule_wrap(function(j_self, _, _)
      if mode == "async" and opts.cb then
        local output = table.concat(j_self:result(), "\n")
        local stderr = table.concat(j_self:stderr_result(), "\n")
        opts.cb(output, stderr)
      end
    end),
    env = get_env(),
  }
  if mode == "sync" then
    job:sync(conf.timeout)
    return table.concat(job:result(), "\n"), table.concat(job:stderr_result(), "\n")
  else
    job:start()
  end
end

local create_flag = function(key)
  if #key == 1 then
    return "-" .. key
  else
    return "--" .. key
  end
end

---Insert the options into the args table
---@param args table the arguments table
---@param options table the options to insert
---@param replace table|nil key value pairs to replace in the key of the options
---@return table the updated args table
M.insert_args = function(args, options, replace)
  replace = replace or {}

  for key, value in pairs(options) do
    if type(key) == "number" then
      table.insert(args, value)
    else
      for k, v in pairs(replace) do
        key = string.gsub(key, k, v)
      end

      local flag = create_flag(key)

      if type(value) == "table" then
        for k, v in pairs(value) do
          if type(v) == "table" then
            for _, vv in ipairs(v) do
              table.insert(args, flag)
              table.insert(args, k .. "[]=" .. vv)
            end
          elseif type(v) == "boolean" then
            if v then
              table.insert(args, flag)
              table.insert(args, k .. "=" .. tostring(v))
            end
          else
            table.insert(args, flag)
            table.insert(args, k .. "=" .. v)
          end
        end
      elseif type(value) == "boolean" then
        if value then
          table.insert(args, flag)
        end
      else
        table.insert(args, flag)
        table.insert(args, value)
      end
    end
  end

  return args
end

---@class GraphQLOpts
---@field query string|nil
---@field fields table|nil
---@field paginate boolean|nil
---@field slurp boolean|nil
---@field F table|nil field
---@field f table|nil raw-field
---@field jq string|nil

---Create the arguments for the graphql query
---@param opts GraphQLOpts
---@return table|nil
M.create_graphql_opts = function(opts)
  -- add query to the existing raw-field
  local f = opts.f or {}
  local query = opts.query or f.query
  if not query then
    return
  end
  opts.query = nil

  f.query = query
  opts.f = f

  -- Join F and fields together
  local F = opts.F or {}
  local fields = opts.fields or {}

  opts.fields = nil

  opts.F = vim.tbl_extend("force", F, fields)

  return opts
end

--- The gh.api commands
M.api = {}

---Run a graphql query
---@param opts table the options for the graphql query
---@return table|nil
function M.api.graphql(opts)
  opts = opts or {}
  local run_opts = opts.opts or {}

  opts.opts = nil
  local graphql_opts = M.create_graphql_opts(opts)

  if not graphql_opts then
    local utils = require "octo.utils"
    utils.error "Provide query directly or in the f table."
    return
  end

  local args = { "api", "graphql" }
  args = M.insert_args(args, graphql_opts, { ["_"] = "-" })

  return run {
    args = args,
    mode = run_opts.mode,
    cb = run_opts.cb,
    stream_cb = run_opts.stream_cb,
    headers = run_opts.headers,
    hostname = run_opts.hostname,
  }
end

---Format the endpoint with the format table
---@param endpoint string the endpoint to format
---@param format table<key, value> the format table
local format_endpoint = function(endpoint, format)
  for key, value in pairs(format) do
    endpoint = endpoint:gsub("{" .. key .. "}", value)
  end
  return endpoint
end

---@param method string the rest method
---@param opts table the options for the rest command
---@return table|nil
M.create_rest_args = function(method, opts)
  local format = opts.format or {}

  local endpoint = opts[1]
  if not endpoint then
    return
  end
  endpoint = format_endpoint(endpoint, format)
  opts[1] = endpoint

  local args = { "api" }
  if method ~= nil then
    table.insert(args, "--method")
    table.insert(args, method)
  end

  opts.format = nil
  opts.opts = nil
  return M.insert_args(args, opts)
end

---Run a rest command
local rest = function(method, opts)
  local run_opts = opts.opts or {}

  local args = M.create_rest_args(method, opts)
  if not args then
    local utils = require "octo.utils"
    utils.error "Endpoint is required"
    return
  end

  run {
    args = args,
    mode = run_opts.mode,
    cb = run_opts.cb,
    stream_cb = run_opts.stream_cb,
    headers = run_opts.headers,
    hostname = run_opts.hostname,
  }
end

M.api.get = function(opts)
  return rest("GET", opts)
end

M.api.post = function(opts)
  return rest("POST", opts)
end

M.api.patch = function(opts)
  return rest("PATCH", opts)
end

M.api.delete = function(opts)
  return rest("DELETE", opts)
end

M.api.put = function(opts)
  return rest("PUT", opts)
end

---Call the api without specifying the method. GitHub CLI determines the method based on the arguments
setmetatable(M.api, {
  __call = function(_, opts)
    return rest(nil, opts)
  end,
})

local create_subcommand = function(command)
  local subcommand = {}
  subcommand.command = command

  setmetatable(subcommand, {
    __call = function(_, opts)
      --- Allow for backwards compatibility with the old API gh.run { ... }
      if command == "run" then
        return run(opts)
      end
    end,
    __index = function(t, key)
      return function(opts)
        opts = opts or {}

        local run_opts = opts.opts or {}

        local args = {
          t.command,
          key,
        }

        opts.opts = nil
        args = M.insert_args(args, opts, { ["_"] = "-" })

        return run {
          args = args,
          mode = run_opts.mode,
          cb = run_opts.cb,
          stream_cb = run_opts.stream_cb,
          headers = run_opts.headers,
          hostname = run_opts.hostname,
        }
      end
    end,
  })

  return subcommand
end

setmetatable(M, {
  __index = function(_, key)
    return create_subcommand(key)
  end,
})

return M
