local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local writers = require "octo.ui.writers"
local previewers = require "telescope.previewers"
local ts_utils = require "telescope.utils"
local defaulter = ts_utils.make_default_callable

local issue = defaulter(function(opts)
  local backend = require "octo.backend"
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(bufnr) == 1 then
        local func = backend.get_funcs()["telescope_default_issue"]
        func(entry, bufnr)
      end
    end,
  }
end)

local gist = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(bufnr) == 1 then
        local file = entry.gist.files[1]
        if file.text then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(file.text, "\n"))
        else
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.gist.description)
        end
        vim.api.nvim_buf_call(bufnr, function()
          pcall(vim.cmd, "set filetype=" .. string.gsub(file.extension, "\\.", ""))
        end)
      end
    end,
  }
end)

local commit = defaulter(function(opts)
  local backend = require "octo.backend"
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    keep_last_buf = true,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(self.state.bufnr) == 1 then
        local lines = {}
        vim.list_extend(lines, { string.format("Commit: %s", entry.value) })
        vim.list_extend(lines, { string.format("Author: %s", entry.author) })
        vim.list_extend(lines, { string.format("Date: %s", entry.date) })
        vim.list_extend(lines, { "" })
        vim.list_extend(lines, vim.split(entry.msg, "\n"))
        vim.list_extend(lines, { "" })
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

        local func = backend.get_funcs()["telescope_default_commit"]
        func(entry, opts.repo, self.state.bufname, self.state.bufnr)
      end
    end,
  }
end, {})

local changed_files = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    keep_last_buf = true,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(self.state.bufnr) == 1 then
        local diff = entry.change.patch
        if diff then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(diff, "\n"))
          vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "diff")
        end
      end
    end,
  }
end, {})

local review_thread = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(bufnr) == 1 then
        local buffer = OctoBuffer:new {
          bufnr = bufnr,
        }
        buffer:configure()
        writers.write_threads(bufnr, { entry.thread })
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd [[setlocal foldmethod=manual]]
          vim.cmd [[normal! zR]]
        end)
      end
    end,
  }
end, {})

local issue_template = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(self.state.bufnr) == 1 then
        local template = entry.template.body
        if template then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(template, "\n"))
          vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
        end
      end
    end,
  }
end, {})

return {
  issue = issue,
  gist = gist,
  commit = commit,
  changed_files = changed_files,
  review_thread = review_thread,
  issue_template = issue_template,
}
