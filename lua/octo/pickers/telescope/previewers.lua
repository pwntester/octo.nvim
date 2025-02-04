local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local previewers = require "telescope.previewers"
local pv_utils = require "telescope.previewers.utils"
local ts_utils = require "telescope.utils"
local defaulter = ts_utils.make_default_callable

local vim = vim

local discussion = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr

      if self.state.bufname == entry.value and vim.api.nvim_buf_line_count(bufnr) ~= 1 then
        return
      end

      local number = entry.value
      local owner, name = utils.split_repo(entry.repo)
      local query = graphql("discussion_query", owner, name, number)

      gh.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
          if stderr and not utils.is_blank(stderr) then
            vim.api.nvim_err_writeln(stderr)
          elseif output and vim.api.nvim_buf_is_valid(bufnr) then
            -- clear the buffer
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

            local result = vim.json.decode(output)
            local obj = result.data.repository.discussion

            writers.write_title(bufnr, tostring(obj.title), 1)
            writers.write_discussion_details(bufnr, obj)
            writers.write_body(bufnr, obj, 11)

            if obj.answer ~= vim.NIL then
              local line = vim.api.nvim_buf_line_count(bufnr) + 1
              writers.write_discussion_answer(bufnr, obj, line)
            end

            vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
          end
        end,
      }
    end,
  }
end)

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
        local owner, name = utils.split_repo(entry.repo)
        local query
        if entry.kind == "issue" then
          query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
        elseif entry.kind == "pull_request" then
          query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
        end
        gh.run {
          args = { "api", "graphql", "-f", string.format("query=%s", query) },
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output and vim.api.nvim_buf_is_valid(bufnr) then
              local result = vim.json.decode(output)
              local obj
              if entry.kind == "issue" then
                obj = result.data.repository.issue
              elseif entry.kind == "pull_request" then
                obj = result.data.repository.pullRequest
              end

              local state = utils.get_displayed_state(entry.kind == "issue", obj.state, obj.stateReason)

              writers.write_title(bufnr, obj.title, 1)
              writers.write_details(bufnr, obj)
              writers.write_body(bufnr, obj)
              writers.write_state(bufnr, state:upper(), number)
              local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
              writers.write_block(bufnr, { "", "" }, reactions_line)
              writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
              vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
            end
          end,
        }
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
        local cmd = { "gh", "api", "--paginate", url, "-H", "Accept: application/vnd.github.v3.diff" }
        pv_utils.job_maker(cmd, self.state.bufnr, {
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
  discussion = discussion,
  issue = issue,
  gist = gist,
  commit = commit,
  changed_files = changed_files,
  review_thread = review_thread,
  issue_template = issue_template,
}
