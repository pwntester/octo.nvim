require "octo"
local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local previewers = require "telescope.previewers"
local utils = require "octo.utils"
local ts_utils = require "telescope.utils"
local pv_utils = require "telescope.previewers.utils"
local writers = require "octo.writers"
local graphql = require "octo.graphql"
local gh = require "octo.gh"
local host = require "octo.host.provider"
local defaulter = ts_utils.make_default_callable

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

local issue = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(bufnr) == 1 then
        local number = entry.value
        local cb = function(obj, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif obj and vim.api.nvim_buf_is_valid(bufnr) then
              writers.write_title(bufnr, obj.title, 1)
              writers.write_details(bufnr, obj)
              writers.write_body(bufnr, obj)
              writers.write_state(bufnr, obj.state:upper(), number)
              local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
              writers.write_block(bufnr, { "", "" }, reactions_line)
              writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
              vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
            end
          end


        if entry.kind == "issue" then
          host:get_issue(entry.repo, entry.value, cb)
        elseif entry.kind == "pull_request" then
          -- TODO
          print("TODO")
        end
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

        local url = string.format("/repos/%s/commits/%s", opts.repo, entry.value)
        pv_utils.job_maker({ "glab", "api", url, "-H", "Accept: application/vnd.github.v3.diff" }, self.state.bufnr, {
          value = entry.value,
          bufname = self.state.bufname,
          mode = "append",
          callback = function(bufnr, _)
            vim.api.nvim_buf_set_option(bufnr, "filetype", "diff")
            vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoDetailsLabel", 0, 0, string.len "Commit:")
            vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoDetailsLabel", 1, 0, string.len "Author:")
            vim.api.nvim_buf_add_highlight(bufnr, -1, "OctoDetailsLabel", 2, 0, string.len "Date:")
          end,
        })
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

return {
  issue = issue,
  gist = gist,
  commit = commit,
  changed_files = changed_files,
  review_thread = review_thread,
}
