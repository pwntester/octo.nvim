local config = require "octo.config"
local _, Job = pcall(require, "plenary.job")

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
}

local function get_env()
  local env = env_vars
  local gh_env = config.get_config().gh_env
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
function M.get_user_name()
  local job = Job:new {
    enable_recording = true,
    command = "gh",
    args = { "auth", "status" },
    env = get_env(),
  }
  job:sync()
  local stderr = table.concat(job:stderr_result(), "\n")
  local name = string.match(stderr, "Logged in to [^%s]+ as ([^%s]+)")
  if name then
    return name
  else
    require("octo.utils").error(stderr)
  end
end

function M.run(opts)
  if not Job then
    return
  end

  -- Lazy load viewer name on the first gh command
  if not vim.g.octo_viewer then
    vim.g.octo_viewer = M.get_user_name()
  end

  opts = opts or {}
  local conf = config.get_config()
  local mode = opts.mode or "async"
  local hostname = ""
  local remote_hostname = require("octo.utils").get_remote_host()
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
    command = "gh",
    args = opts.args,
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
    job:sync()
    return table.concat(job:result(), "\n"), table.concat(job:stderr_result(), "\n")
  else
    job:start()
  end
end

return M
