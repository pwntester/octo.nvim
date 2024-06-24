local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local builtin = require "fzf-lua.previewer.builtin"
local config = require "octo.config"

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
  local path, line = entry_str:match "([^:]+):?(.*)"
  return {
    path = path,
    line = tonumber(line) or 1,
    col = 1,
  }
end

-- Disable line numbering and word wrap
function M.bufferPreviewer:gen_winopts()
  local new_winopts = {
    wrap = false,
    number = false,
  }
  return vim.tbl_extend("force", self.winopts, new_winopts)
end

function M.bufferPreviewer:update_border(title)
  self.win:update_title(title)
  self.win:update_scrollbar()
end

M.issue = function(formatted_issues)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    self.title = "Issues"
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_issues[entry_str]
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_default_issue"]
    func(entry, tmpbuf)

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

M.search = function()
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    self.title = "Issues"
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local match = string.gmatch(entry_str, "[^%s]+")
    local kind = match()
    local owner = match()
    local name = match()
    local number = tonumber(match())

    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_previewer_search"]
    func(kind, number, owner, name, tmpbuf)

    self:set_preview_buf(tmpbuf)
    -- self:update_border(number.." "..description)
    self.win:update_scrollbar()
  end

  return previewer
end

M.commit = function(formatted_commits, repo)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_commits[entry_str]

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

    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_default_commit"]
    local output = func(repo, entry.value)

    vim.api.nvim_buf_set_lines(tmpbuf, #lines, -1, false, vim.split(output, "\n"))

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

M.changed_files = function(formatted_files)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_files[entry_str]

    local diff = entry.change.patch
    if diff then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(diff, "\n"))
      vim.api.nvim_buf_set_option(tmpbuf, "filetype", "git")
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

M.review_thread = function(formatted_threads)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_threads[entry_str]

    local buffer = OctoBuffer:new {
      bufnr = tmpbuf,
    }
    buffer:configure()
    buffer:render_threads { entry.thread }
    vim.api.nvim_buf_call(tmpbuf, function()
      vim.cmd [[setlocal foldmethod=manual]]
      vim.cmd [[normal! zR]]
    end)

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

M.gist = function(formatted_gists)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()

    local entry = formatted_gists[entry_str]

    local file = entry.gist.files[1]
    if file.text then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(file.text, "\n"))
    else
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, entry.gist.description)
    end
    vim.api.nvim_buf_call(tmpbuf, function()
      pcall(vim.cmd, "set filetype=" .. string.gsub(file.extension, "\\.", ""))
    end)

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.gist.description)
  end

  return previewer
end

M.repo = function(formatted_repos)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_repos[entry_str]

    local buffer = OctoBuffer:new {
      bufnr = tmpbuf,
    }
    buffer:configure()
    local repo_name_owner = vim.split(entry_str, " ")[1]
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_previewer_repos"]
    func(buffer, repo_name_owner, tmpbuf)

    self:set_preview_buf(tmpbuf)

    local stargazer, fork
    if config.values.picker_config.use_emojis then
      stargazer = string.format("💫: %s", entry.repo.stargazerCount)
      fork = string.format("🔱: %s", entry.repo.forkCount)
    else
      stargazer = string.format("s: %s", entry.repo.stargazerCount)
      fork = string.format("f: %s", entry.repo.forkCount)
    end
    self:update_border(string.format("%s (%s, %s)", repo_name_owner, stargazer, fork))
  end

  return previewer
end

M.issue_template = function(formatted_templates)
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_templates[entry_str]
    local template = entry.template.body

    if template then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(template, "\n"))
      vim.api.nvim_buf_set_option(tmpbuf, "filetype", "markdown")
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.value)
    self.win:update_scrollbar()
  end

  return previewer
end

return M
