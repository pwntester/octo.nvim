local Job = require("plenary.job")

local function run(opts)
  opts = opts or {}

  local mode = opts.mode or "async"
  local stdout_results = {}
  local stderr_results = {}

  if opts.args[1] ~= "auth" and opts.args[1] ~= "pr" then
    table.insert(opts.args, "-H")
    table.insert(opts.args, "Accept: application/vnd.github.squirrel-girl-preview+json")
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
      on_stdout = function(_, line)
        table.insert(stdout_results, line)
      end,
      on_stderr = function(_, line)
        table.insert(stderr_results, line)
      end,
      on_exit = vim.schedule_wrap(
        function(j_self, _, _)
          if mode == "async" and opts.cb then
            opts.cb(table.concat(j_self:result()), table.concat(j_self:stderr_result()))
          end
        end
      )
    }
  )
  if mode == "sync" then
    job:sync()
    return table.concat(job:result(), "\n")
  else
    job:start()
  end
end

return {
  run = run
}
