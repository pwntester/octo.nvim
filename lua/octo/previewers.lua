local previewers = require "telescope.previewers"
local utils = require "telescope.utils"
local putils = require "telescope.previewers.utils"
local writers = require "octo.writers"
local graphql = require "octo.graphql"
local util = require "octo.util"
local gh = require "octo.gh"
local constants = require "octo.constants"
local defaulter = utils.make_default_callable
local flatten = vim.tbl_flatten
local format = string.format
local api = vim.api
local json = {
  parse = vim.fn.json_decode,
}

local M = {}

M.issue =
  defaulter(
  function(opts)
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          local number = entry.issue.number
          local owner, name = util.split_repo(opts.repo)
          local query = graphql("issue_query", owner, name, number)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output and api.nvim_buf_is_valid(bufnr) then
                  local result = json.parse(output)
                  local issue = result.data.repository.issue
                  writers.write_title(bufnr, issue.title, 1)
                  writers.write_details(bufnr, issue)
                  writers.write_body(bufnr, issue)
                  writers.write_state(bufnr, issue.state:upper(), number)
                  --writers.write_reactions(bufnr, issue.reactions, api.nvim_buf_line_count(bufnr) - 1)
                  api.nvim_buf_set_option(bufnr, "filetype", "octo_issue")
                end
              end
            }
          )
        end
      end
    }
  end
)

M.gist =
  defaulter(
  function(opts)
    return previewers.new_termopen_previewer {
      get_command = opts.get_command or function(entry)
          local tmp_table = vim.split(entry.value, "\t")
          if vim.tbl_isempty(tmp_table) then
            return {"echo", ""}
          end
          local result = {"gh", "gist", "view", tmp_table[1], "|"}
          if vim.fn.executable("bat") then
            table.insert(result, {"bat", "--style=plain", "--color=always", "--paging=always", "--decorations=never", "--pager=less"})
          else
            table.insert(result, "less")
          end
          return flatten(result)
        end
    }
  end,
  {}
)

M.pull_request =
  defaulter(
  function(opts)
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          local number = entry.pull_request.number
          local owner, name = util.split_repo(opts.repo)
          local query = graphql("pull_request_query", owner, name, number)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output and api.nvim_buf_is_valid(bufnr) then
                  local result = json.parse(output)
                  local pull_request = result.data.repository.pullRequest
                  writers.write_title(bufnr, pull_request.title, 1)
                  writers.write_details(bufnr, pull_request)
                  writers.write_body(bufnr, pull_request)
                  writers.write_state(bufnr, pull_request.state:upper(), number)
                  writers.write_reactions(
                    bufnr,
                    pull_request.reactionGroups,
                    api.nvim_buf_line_count(bufnr) - 1
                  )
                  api.nvim_buf_set_option(bufnr, "filetype", "octo_issue")
                end
              end
            }
          )
        end
      end
    }
  end
)

M.commit =
  defaulter(
  function(opts)
    return previewers.new_buffer_previewer {
      keep_last_buf = true,
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(self.state.bufnr) == 1 then
          local lines = {}
          vim.list_extend(lines, {format("Commit: %s", entry.value)})
          vim.list_extend(lines, {format("Author: %s", entry.author)})
          vim.list_extend(lines, {format("Date: %s", entry.date)})
          vim.list_extend(lines, {""})
          vim.list_extend(lines, vim.split(entry.msg, "\n"))
          vim.list_extend(lines, {""})
          api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

          local url = format("/repos/%s/commits/%s", opts.repo, entry.value)
          putils.job_maker(
            {"gh", "api", url, "-H", "Accept: application/vnd.github.v3.diff"},
            self.state.bufnr,
            {
              value = entry.value,
              bufname = self.state.bufname,
              mode = "append",
              callback = function(bufnr, _)
                api.nvim_buf_set_option(bufnr, "filetype", "diff")
                api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimDetailsLabel", 0, 0, string.len("Commit:"))
                api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimDetailsLabel", 1, 0, string.len("Author:"))
                api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimDetailsLabel", 2, 0, string.len("Date:"))
              end
            }
          )
        end
      end
    }
  end,
  {}
)

M.changed_files =
  defaulter(
  function()
    return previewers.new_buffer_previewer {
      keep_last_buf = true,
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(self.state.bufnr) == 1 then
          local diff = entry.change.patch
          if diff then
            api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(diff, "\n"))
            api.nvim_buf_set_option(self.state.bufnr, "filetype", "diff")
          end
        end
      end
    }
  end,
  {}
)

M.review_comment =
  defaulter(
  function()
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          -- TODO: pretty print
          writers.write_diff_hunk(bufnr, entry.comment.diffHunk)
          api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.split(entry.comment.body, "\n"))
        end
      end
    }
  end,
  {}
)

return M
