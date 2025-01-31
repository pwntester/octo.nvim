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

function M.run(opts)
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
---@return table the updated args table
M.insert_args = function(args, options)
  for key, value in pairs(options) do
    if type(key) == "number" then
      table.insert(args, value)
    else
      local flag = create_flag(key)

      if type(value) == "table" then
        for k, v in pairs(value) do
          if type(v) == "table" then
            for _, vv in ipairs(v) do
              table.insert(args, flag)
              table.insert(args, k .. "[]=" .. vv)
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

---Create the arguments for the graphql query
---@param query string the graphql query
---@param fields table key value pairs for graphql query
---@param paginate boolean whether to paginate the results
---@param slurp boolean whether to slurp the results
---@param jq string the jq query to apply to the results
---@return table
local create_graphql_args = function(query, fields, paginate, slurp, jq)
  local args = { "api", "graphql" }

  local opts = {
    f = {
      query = query,
    },
    F = fields,
    paginate = paginate,
    slurp = slurp,
    jq = jq,
  }

  return M.insert_args(args, opts)
end

---Run a graphql query
---@param opts table the options for the graphql query
---@return table|nil
function M.graphql(opts)
  local run_opts = opts.opts or {}
  return M.run {
    args = create_graphql_args(opts.query, opts.fields, opts.paginate, opts.slurp, opts.jq),
    mode = run_opts.mode,
    cb = run_opts.cb,
    stream_cb = run_opts.stream_cb,
    headers = run_opts.headers,
    hostname = run_opts.hostname,
  }
end

M.api = {
  graphql = M.graphql,
}

local create_subcommand = function(command)
  local subcommand = {}
  subcommand.command = command

  setmetatable(subcommand, {
    __index = function(t, key)
      return function(opts)
        opts = opts or {}

        local run_opts = opts.opts or {}

        local args = {
          t.command,
          key,
        }

        opts.opts = nil
        args = M.insert_args(args, opts)

        return M.run {
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
