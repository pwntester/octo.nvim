local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

return function (opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  local url = string.format("repos/%s/pulls/%d/files", buffer.repo, buffer.number)
  gh.run {
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.fn.json_decode(output)

        local formatted_files = {}
        local titles = {}

        for _, result in ipairs(results) do
          local entry = entry_maker.gen_from_git_changed_files(result)

          if entry ~= nil then
            formatted_files[entry.ordinal] = entry
            table.insert(titles, entry.ordinal)
          end
        end

        fzf.fzf_exec(titles, {
          prompt = opts.prompt_title or "",
          -- TODO What is this?
          -- opts.preview_title = opts.preview_title or "",
          previewer = previewers.changed_files(formatted_files),
          -- TODO actions not implemented here, what is the use of this exactly?
          -- actions = {
          --   ['default'] = function (selected, opts)
          --     log.info(opts)
          --     local bufnr = opts:get_tmp_buffer()
          --     local entry = formatted_commits[selected[1]]
          --     picker_utils.open_preview_buffer('default', bufnr, entry)
          --   end,
          --   ['ctrl-v'] = function (selected)
          --     local bufnr = opts:get_tmp_buffer()
          --     local entry = formatted_commits[selected[1]]
          --     picker_utils.open_preview_buffer('vertical', bufnr, entry)
          --   end,
          --   ['ctrl-s'] = function (selected)
          --     local bufnr = opts:get_tmp_buffer()
          --     local entry = formatted_commits[selected[1]]
          --     picker_utils.open_preview_buffer('horizontal', bufnr, entry)
          --   end,
          --   ['ctrl-t'] = function (selected)
          --     local bufnr = opts:get_tmp_buffer()
          --     local entry = formatted_commits[selected[1]]
          --     picker_utils.open_preview_buffer('tab', bufnr, entry)
          --   end,
          -- },
        })
      end
    end,
  }
end
