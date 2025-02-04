local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

return function(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end

  local formatted_commits = {}

  local get_contents = function(fzf_cb)
    local url = string.format("repos/%s/pulls/%d/commits", buffer.repo, buffer.number)
    gh.run {
      args = { "api", "--paginate", url },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local results = vim.json.decode(output)

          for _, result in ipairs(results) do
            local entry = entry_maker.gen_from_git_commits(result)

            if entry ~= nil then
              formatted_commits[entry.ordinal] = entry
              fzf_cb(entry.ordinal)
            end
          end
        end

        fzf_cb()
      end,
    }
  end

  fzf.fzf_exec(get_contents, {
    prompt = opts.prompt_title or "",
    fzf_opts = {
      ["--delimiter"] = "' '",
      ["--info"] = "default",
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--with-nth"] = "2..",
    },
    previewer = previewers.commit(formatted_commits, buffer.repo),
    actions = fzf_actions.common_buffer_actions(formatted_commits),
  })
end
