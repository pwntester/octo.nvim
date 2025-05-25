local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local previewers = require "telescope.previewers"
local pv_utils = require "telescope.previewers.utils"
local ts_utils = require "telescope.utils"
local release = require "octo.release"
local defaulter = ts_utils.make_default_callable
local workflow_runs_previewer = require("octo.workflow_runs").previewer

local vim = vim

local function discussion_preview(obj, bufnr)
  -- clear the buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  local state = obj.closed and "CLOSED" or "OPEN"
  writers.write_title(bufnr, tostring(obj.title), 1)
  writers.write_state(bufnr, state, obj.number)
  writers.write_discussion_details(bufnr, obj)
  writers.write_body(bufnr, obj, 13)

  if obj.answer ~= vim.NIL then
    local line = vim.api.nvim_buf_line_count(bufnr) + 1
    writers.write_discussion_answer(bufnr, obj, line)
  end

  vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
end

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
            failure = vim.api.nvim_err_writeln,
            success = function(output)
              if not vim.api.nvim_buf_is_valid(bufnr) then
                return
              end

              local obj = vim.json.decode(output)
              discussion_preview(obj, bufnr)
            end,
          },
        },
      }
    end,
  }
end)

local function issue_preview(obj, bufnr)
  local state = utils.get_displayed_state(obj.__typename == "Issue", obj.state, obj.stateReason)
  writers.write_title(bufnr, obj.title, 1)
  writers.write_details(bufnr, obj)
  writers.write_body(bufnr, obj)
  writers.write_state(bufnr, state:upper(), obj.number)
  local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
  writers.write_block(bufnr, { "", "" }, reactions_line)
  writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
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
              failure = vim.api.nvim_err_writeln,
              success = function(output)
                local obj = vim.json.decode(output)

                if not vim.api.nvim_buf_is_loaded(bufnr) then
                  return
                end

                issue_preview(obj, bufnr)
              end,
            },
          },
        }
      end
    end,
  }
end)

---@param obj octo.Release
---@param bufnr integer
local function release_preview(obj, bufnr)
  writers.write_release(bufnr, obj)
  vim.bo[bufnr].filetype = "octo"
end

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
        local number = entry.value ---@type string
        local owner, name = utils.split_repo(entry.repo)

        ---@type string, table<string, string>, string, fun(obj: any, bufnr: integer): nil
        local query, fields, jq, preview

        local function fetch_and_preview()
          gh.api.graphql {
            query = query,
            fields = fields,
            jq = jq,
            opts = {
              cb = gh.create_callback {
                failure = vim.api.nvim_err_writeln,
                success = function(output)
                  if not vim.api.nvim_buf_is_loaded(bufnr) then
                    return
                  end

                  local ok, obj = pcall(vim.json.decode, output)
                  if not ok then
                    utils.error("Failed to parse preview data: " .. vim.inspect(output))
                    return
                  end

                  preview(obj, bufnr)
                end,
              },
            },
          }
        end
        if entry.kind == "issue" then
          query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
          fields = {}
          jq = ".data.repository.issue"
          preview = issue_preview
        elseif entry.kind == "pull_request" then
          query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
          fields = {}
          jq = ".data.repository.pullRequest"
          preview = issue_preview
        elseif entry.kind == "discussion" then
          query = queries.discussion
          fields = { owner = owner, name = name, number = number }
          jq = ".data.repository.discussion"
          preview = discussion_preview
        elseif entry.kind == "release" then
          -- GraphQL only accepts tags and release notifications give back IDs
          release.get_tag_from_release_id(entry, function(tag_name)
            entry.tag_name = tag_name
            query = queries.release
            fields = { owner = owner, name = name, tag = tag_name }
            jq = ".data.repository.release"
            preview = release_preview
            fetch_and_preview()
          end)
          return
        end
        fetch_and_preview()
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

local workflow_runs = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    define_preview = workflow_runs_previewer,
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
}
