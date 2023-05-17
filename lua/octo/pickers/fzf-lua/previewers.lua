local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local builtin = require "fzf-lua.previewer.builtin"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local utils = require "octo.utils"
local writers = require "octo.ui.writers"

local M = {}

-- Inherit from the "buffer_or_file" previewer
M.bufferPreviewer = builtin.buffer_or_file:extend()

function M.bufferPreviewer:new(o, opts, fzf_win)
  M.bufferPreviewer.super.new(self, o, opts, fzf_win)
  setmetatable(self, M.bufferPreviewer)
  -- self.title = true
  return self
end

function M.bufferPreviewer:parse_entry(entry_str)
  -- Assume an arbitrary entry in the format of 'file:line'
  local path, line = entry_str:match("([^:]+):?(.*)")
  return {
    path = path,
    line = tonumber(line) or 1,
    col = 1,
  }
end

-- Disable line numbering and word wrap
function M.bufferPreviewer:gen_winopts()
  local new_winopts = {
    wrap   = false,
    number = false,
  }
  return vim.tbl_extend("force", self.winopts, new_winopts)
end

function M.bufferPreviewer:update_border(entry)
  self.win:update_title(entry.ordinal)
  self.win:update_scrollbar()
end

M.issue = function(formattedIssues)
  local issuePreviewer = M.bufferPreviewer:extend()

  function issuePreviewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    self.title = 'Issues'
    setmetatable(self, issuePreviewer)
    return self
  end

  function issuePreviewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formattedIssues[entry_str]

    local number = entry.value
    local owner, name = utils.split_repo(entry.repo)
    local query
    if entry.kind == "issue" then
      query = graphql("issue_query", owner, name, number)
    elseif entry.kind == "pull_request" then
      query = graphql("pull_request_query", owner, name, number)
    end
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output and vim.api.nvim_buf_is_valid(tmpbuf) then
          local result = vim.fn.json_decode(output)
          local obj
          if entry.kind == "issue" then
            obj = result.data.repository.issue
          elseif entry.kind == "pull_request" then
            obj = result.data.repository.pullRequest
          end
          writers.write_title(tmpbuf, obj.title, 1)
          writers.write_details(tmpbuf, obj)
          writers.write_body(tmpbuf, obj)
          writers.write_state(tmpbuf, obj.state:upper(), number)
          local reactions_line = vim.api.nvim_buf_line_count(tmpbuf) - 1
          writers.write_block(tmpbuf, { "", "" }, reactions_line)
          writers.write_reactions(tmpbuf, obj.reactionGroups, reactions_line)
          vim.api.nvim_buf_set_option(tmpbuf, "filetype", "octo")
          vim.api.nvim_buf_set_name(tmpbuf, entry.filename)
          -- local lines = vim.api.nvim_buf_get_lines(tmpbuf, 0, -1, false)
          -- entry.body = lines
        end
      end,
    }

    self:set_preview_buf(tmpbuf)
    self:update_border(entry)
    self.win:update_scrollbar()
  end

  return issuePreviewer
end

M.commit = function(formattedCommits, repo)
  local commitPreviewer = M.bufferPreviewer:extend()

  function commitPreviewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, commitPreviewer)
    return self
  end

  function commitPreviewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formattedCommits[entry_str]

    local lines = {}
    vim.list_extend(lines, { string.format("Commit: %s", entry.value) })
    vim.list_extend(lines, { string.format("Author: %s", entry.author) })
    vim.list_extend(lines, { string.format("Date: %s", entry.date) })
    vim.list_extend(lines, { "" })
    vim.list_extend(lines, vim.split(entry.msg, "\n"))
    vim.list_extend(lines, { "" })
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(tmpbuf, "filetype", "git")
    vim.api.nvim_buf_add_highlight(tmpbuf, -1, "OctoDetailsLabel", 0, 0, string.len "Commit:")
    vim.api.nvim_buf_add_highlight(tmpbuf, -1, "OctoDetailsLabel", 1, 0, string.len "Author:")
    vim.api.nvim_buf_add_highlight(tmpbuf, -1, "OctoDetailsLabel", 2, 0, string.len "Date:")

    local url = string.format("/repos/%s/commits/%s", repo, entry.value)
    local cmd = table.concat({ "gh", "api", url, "-H", "'Accept: application/vnd.github.v3.diff'" }, ' ')
    local proc = io.popen(cmd, 'r')
    local output
    if proc ~= nil then
      output = proc:read('*a')
      proc:close()
    else
      output = "Failed to read from " .. url
    end

    vim.api.nvim_buf_set_lines(tmpbuf, #lines, -1, false, vim.split(output, '\n'))


    self:set_preview_buf(tmpbuf)
    self:update_border(entry)
    self.win:update_scrollbar()
  end

  return commitPreviewer
end

M.changed_files = function(formattedFiles)
  local filesPreviewer = M.bufferPreviewer:extend()

  function filesPreviewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, filesPreviewer)
    return self
  end

  function filesPreviewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formattedFiles[entry_str]

    local diff = entry.change.patch
    if diff then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(diff, "\n"))
      vim.api.nvim_buf_set_option(tmpbuf, "filetype", "git")
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry)
    self.win:update_scrollbar()
  end

  return filesPreviewer
end

return M
