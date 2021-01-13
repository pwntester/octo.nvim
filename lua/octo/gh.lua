local Job = require("plenary.job")

local function run(opts)
  opts = opts or {}

  local mode = opts.mode or "async"

  if opts.args[1] == "api" then
    table.insert(opts.args, "-H")
    table.insert(opts.args, "Accept: application/vnd.github.v3+json;application/vnd.github.squirrel-girl-preview+json;application/vnd.github.comfort-fade-preview+json")
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
            local output = table.concat(j_self:result())
            local stderr = table.concat(j_self:stderr_result())
            opts.cb(output, stderr)
          end
        end
      )
    }
  )
  if mode == "sync" then
    job:sync()
    return table.concat(job:result())
  else
    job:start()
  end
end

return {
  run = run
}
