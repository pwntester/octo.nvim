local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local builtin = require "fzf-lua.previewer.builtin"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local utils = require "octo.utils"
local writers = require "octo.ui.writers"
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
  self.win:update_preview_title(title)
  self.win:update_preview_scrollbar()
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
    if entry_str == "" then
      return
    end
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_issues[entry_str]

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
        elseif output and self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
          local result = vim.json.decode(output)
          local obj
          if entry.kind == "issue" then
            obj = result.data.repository.issue
          elseif entry.kind == "pull_request" then
            obj = result.data.repository.pullRequest
          end

          local state = utils.get_displayed_state(entry.kind == "issue", obj.state, obj.stateReason)

          writers.write_title(tmpbuf, obj.title, 1)
          writers.write_details(tmpbuf, obj)
          writers.write_body(tmpbuf, obj)
          writers.write_state(tmpbuf, state:upper(), number)
          local reactions_line = vim.api.nvim_buf_line_count(tmpbuf) - 1
          writers.write_block(tmpbuf, { "", "" }, reactions_line)
          writers.write_reactions(tmpbuf, obj.reactionGroups, reactions_line)
          vim.api.nvim_buf_set_option(tmpbuf, "filetype", "octo")
        end
      end,
    }

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
    if entry_str == "" then
      return
    end
    local tmpbuf = self:get_tmp_buffer()
    local match = string.gmatch(entry_str, "[^%s]+")
    local kind = match()
    local owner = match()
    local name = match()
    local number = tonumber(match())

    local query
    if kind == "issue" then
      query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
    elseif kind == "pull_request" then
      query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
    end
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output and self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
          local result = vim.json.decode(output)
          local obj
          if kind == "issue" then
            obj = result.data.repository.issue
          elseif kind == "pull_request" then
            obj = result.data.repository.pullRequest
          end

          local state = utils.get_displayed_state(kind == "issue", obj.state, obj.stateReason)

          writers.write_title(tmpbuf, obj.title, 1)
          writers.write_details(tmpbuf, obj)
          writers.write_body(tmpbuf, obj)
          writers.write_state(tmpbuf, state:upper(), number)
          local reactions_line = vim.api.nvim_buf_line_count(tmpbuf) - 1
          writers.write_block(tmpbuf, { "", "" }, reactions_line)
          writers.write_reactions(tmpbuf, obj.reactionGroups, reactions_line)
          vim.api.nvim_buf_set_option(tmpbuf, "filetype", "octo")
        end
      end,
    }

    self:set_preview_buf(tmpbuf)
    -- self:update_border(number.." "..description)
    self.win:update_preview_scrollbar()
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
    if entry_str == "" then
      return
    end
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

    local url = string.format("/repos/%s/commits/%s", repo, entry.value)
    local cmd = table.concat({ "gh", "api", "--paginate", url, "-H", "'Accept: application/vnd.github.v3.diff'" }, " ")
    local proc = io.popen(cmd, "r")
    local output
    if proc ~= nil then
      output = proc:read "*a"
      proc:close()
    else
      output = "Failed to read from " .. url
    end

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
    if entry_str == "" then
      return
    end
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
    if entry_str == "" then
      return
    end
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
    if entry_str == "" then
      return
    end
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
    if entry_str == "" then
      return
    end
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_repos[entry_str]

    local buffer = OctoBuffer:new {
      bufnr = tmpbuf,
    }
    buffer:configure()
    local repo_name_owner = vim.split(entry_str, " ")[1]
    local owner, name = utils.split_repo(repo_name_owner)
    local query = graphql("repository_query", owner, name)
    gh.run {
      args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
      cb = function(output, _)
        -- when the entry changes `preview_bufnr` will also change (due to `set_preview_buf`)
        -- and `tmpbuf` within this context is already cleared and invalidated
        if self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
          local resp = vim.json.decode(output)
          buffer.node = resp.data.repository
          buffer:render_repo()
        end
      end,
    }

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
    if entry_str == "" then
      return
    end
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_templates[entry_str]
    local template = entry.template.body

    if template then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(template, "\n"))
      vim.api.nvim_buf_set_option(tmpbuf, "filetype", "markdown")
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.value)
    self.win:update_preview_scrollbar()
  end

  return previewer
end

return M
