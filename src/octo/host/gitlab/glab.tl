local _, Job = pcall(require, "plenary.job")

local M = {}

local env_vars = {
  PATH = vim.env["PATH"],
  GH_CONFIG_DIR = vim.env["GH_CONFIG_DIR"],
  GITLAB_TOKEN = vim.env["GITLAB_TOKEN"],
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

-- uses glab to get the name of the authenticated user
function M.get_user_name(): string
  local job = Job:new {
    enable_recording = true,
    command = "glab",
    args = { "auth", "status" },
    env = env_vars,
  }
  job:sync(nil, nil)
  local stderr = table.concat(job:stderr_result(), "\n")
  local name = string.match(stderr, "Logged in to [^%s]+ as ([^%s]+)")
  if name then
    return name
  else
    require("octo.utils").notify(stderr, 2)
  end
end

global type RunOpts = record
  args: {string}
  headers: {string}
  hostname: string
  cb: function(output: string, stderr: string)

  enum RunMode
    "async"
    "sync"
  end
  mode: RunMode
end

function M.run(opts: RunOpts): string, string
  if not Job then
    return
  end

  -- Lazy load viewer name on the first gh command
  if not vim.g.octo_viewer then
    vim.g.octo_viewer = M.get_user_name()
  end

  opts = opts or {}
  local mode = opts.mode or "async"
  if opts.args[1] == "api" then
    table.insert(opts.args, "--hostname")
    table.insert(opts.args, opts.hostname)
  end

  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(opts.args, "-H")
      table.insert(opts.args, header)
    end
  end

  local job = Job:new {
    enable_recording = true,
    command = "glab",
    args = opts.args,
    on_exit = vim.schedule_wrap(function(j_self: Job, _, _)
      if mode == "async" and opts.cb then
        local output = table.concat(j_self:result(), "\n")
        local stderr = table.concat(j_self:stderr_result(), "\n")
        opts.cb(output, stderr)
      end
    end) as function(Job, number, number),
    env = env_vars,
  }

  if mode == "sync" then
    job:sync()
    return table.concat(job:result(), "\n"), table.concat(job:stderr_result(), "\n")
  else
    job:start()
  end
end

return M
