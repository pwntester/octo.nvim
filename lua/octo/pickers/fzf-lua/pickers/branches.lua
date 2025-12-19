local fzf = require "fzf-lua"

---@type octo.picker.branches
local function _(opts, cb)
  local function get_contents(fzf_cb)
    for _, branch in ipairs(opts.repo.refs.nodes) do
      fzf_cb(branch.name)
    end

    fzf_cb()
  end
  fzf.fzf_exec(get_contents, {
    query = opts.default_branch_name,
    prompt = "> ",
    fzf_opts = {
      ["--no-multi"] = "",
      ["--info"] = "default",
    },
    winopts = {
      title = opts.title or "Select Branch",
      title_pos = "center",
    },
    actions = {
      ["enter"] = function(value)
        cb(value[1])
      end,
    },
  })
end

return _
