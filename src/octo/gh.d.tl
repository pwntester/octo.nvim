-- TODO: We HAVE TO refactor this. To be able to support GitLab!
local record M
  get_user_name: function(): string

  enum RunMode
    "async"
    "sync"
  end

  record RunOpts
    mode: RunMode
    args: {string}
    cb: function(output: string, stderr: string)
  end
  run: function(opts: RunOpts)
end

return M
