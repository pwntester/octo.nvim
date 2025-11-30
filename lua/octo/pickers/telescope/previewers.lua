---@diagnostic disable
local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local gh = require "octo.gh"
local headers = require "octo.gh.headers"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local previewers = require "telescope.previewers"
local pv_utils = require "telescope.previewers.utils"
local ts_utils = require "telescope.utils"
local notifications = require "octo.notifications"
local defaulter = ts_utils.make_default_callable
local workflow_runs_previewer = require("octo.workflow_runs").previewer

local vim = vim

local discussion = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr

      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if self.state.bufname == entry.value and vim.api.nvim_buf_line_count(bufnr) ~= 1 then
        return
      end

      local number = entry.value
      local owner, name = utils.split_repo(entry.repo)

      gh.api.graphql {
        query = queries.discussion,
        fields = { owner = owner, name = name, number = number },
        jq = ".data.repository.discussion",
        opts = {
          cb = gh.create_callback {
            failure = utils.print_err,
            success = function(output)
              if not vim.api.nvim_buf_is_valid(bufnr) then
                return
              end

              local obj = vim.json.decode(output)
              writers.discussion_preview(obj, bufnr)
            end,
          },
        },
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

        local query, jq
        if entry.kind == "issue" then
          query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
          jq = ".data.repository.issue"
        elseif entry.kind == "pull_request" then
          query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
          jq = ".data.repository.pullRequest"
        end

        gh.api.graphql {
          query = query,
          jq = jq,
          opts = {
            cb = gh.create_callback {
              failure = utils.print_err,
              success = function(output)
                local obj = vim.json.decode(output)

                if not vim.api.nvim_buf_is_loaded(bufnr) then
                  return
                end

                writers.issue_preview(obj, bufnr)
              end,
            },
          },
        }
      end
    end,
  }
end)

--- Supports Issues, Pull Requests, and Discussions
local notification = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr

      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(bufnr) == 1 then
        opts.preview_fn(bufnr, entry)
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
        local cmd = { "gh", "api", "--paginate", url, "-H", headers.diff }
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

local workflow_runs = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    define_preview = workflow_runs_previewer,
  }
end, {})

local release = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = opts.preview_title,
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      if self.state.bufname ~= entry.value or vim.api.nvim_buf_line_count(self.state.bufnr) == 1 then
        local data = entry.obj
        if data then
          gh.release.view {
            data.tagName,
            repo = data.repo,
            json = "body",
            jq = ".body",
            opts = {
              cb = gh.create_callback {
                success = function(body)
                  vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(body, "\n"))
                  --- wrap lines
                  vim.api.nvim_set_option_value("filetype", "markdown", {
                    scope = "local",
                    buf = self.state.bufnr,
                  })
                end,
              },
            },
          }
        end
      end
    end,
  }
end, {})

return {
  workflow_runs = workflow_runs,
  discussion = discussion,
  issue = issue,
  gist = gist,
  commit = commit,
  changed_files = changed_files,
  review_thread = review_thread,
  issue_template = issue_template,
  notification = notification,
  release = release,
}
