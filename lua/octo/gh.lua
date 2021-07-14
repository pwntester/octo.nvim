local config = require'octo.config'
local _, Job = pcall(require,'plenary.job')

local headers = {
  "application/vnd.github.v3+json",
  "application/vnd.github.squirrel-girl-preview+json",
  "application/vnd.github.comfort-fade-preview+json",
  "application/vnd.github.bane-preview+json",
}

local env_vars = {
  PATH = vim.env["PATH"],
  GH_CONFIG_DIR = vim.env["GH_CONFIG_DIR"],
  XDG_CONFIG_HOME = vim.env["XDG_CONFIG_HOME"],
  XDG_DATA_HOME = vim.env["XDG_DATA_HOME"],
  XDG_STATE_HOME = vim.env["XDG_STATE_HOME"],
  AppData = vim.env["AppData"],
  LocalAppData = vim.env["LocalAppData"],
  HOME = vim.env["HOME"],
  NO_COLOR = 1
}

local function run(opts)
  if not Job then return end
  opts = opts or {}
  local conf = config.get_config()
  local mode = opts.mode or "async"
  if opts.args[1] == "api" then
    table.insert(opts.args, "-H")
    table.insert(opts.args, "Accept: "..table.concat(headers, ";"))
    if not require"octo.utils".is_blank(conf.github_hostname) then
      table.insert(opts.args, "--hostname")
      table.insert(opts.args, conf.github_hostname)
    end
  end

  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(opts.args, "-H")
      table.insert(opts.args, header)
    end
  end

  local job =
    Job:new(
    {
      enable_recording = true,
      command = "gh",
      args = opts.args,
      on_exit = vim.schedule_wrap(
        function(j_self, _, _)
          if mode == "async" and opts.cb then
            local output = table.concat(j_self:result(), "\n")
            local stderr = table.concat(j_self:stderr_result(), "\n")
            opts.cb(output, stderr)
          end
        end
      ),
      env = env_vars
    }
  )
  if mode == "sync" then
    job:sync()
    return table.concat(job:result(), "\n"), table.concat(job:stderr_result(), "\n")
  else
    job:start()
  end
end

return {
  run = run
}
