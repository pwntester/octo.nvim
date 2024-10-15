local Window = {}
Window.__index = Window

local function get_default_win_opts()
  local width = math.floor(vim.o.columns / 2) - 2
  local height = 20
  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded"
  }
end

local function update_win_opts(win, opts)
  if win == nil then
    return
  end
  vim.api.nvim_win_set_config(win, opts)
end


function Window.new_float()
  local self = setmetatable({}, Window)
  self.buf = vim.api.nvim_create_buf(false, true)
  self.opts = get_default_win_opts()
  self.buf_opts = {
    modifiable = false,
    filetype = nil
  }
  self.callbacks = {}
  return self
end

function Window:buf_set_filetype(filetype)
  if self.buf ~= nil then
    vim.api.nvim_set_option_value('filetype', filetype, { buf = self.buf })
  end

  self.buf_opts.filetype = filetype
  return self
end

function Window:on_win_close(callback)
  if self.win == nil then
    table.insert(self.callbacks, callback)
    return self
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      if tonumber(event.match) == self.win then
        callback()
      end
    end
  })

  return self
end

local function set_buf_opts(buf, opts)
  vim.api.nvim_set_option_value('filetype', opts.filetype, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', opts.modifiable, { buf = buf })
end

function Window:write_buf(lines)
  vim.api.nvim_set_option_value('modifiable', true, { buf = self.buf })
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  set_buf_opts(self.buf, self.buf_opts)
  return self
end

function Window:close()
  vim.api.nvim_win_close(self.win, true)
end

function Window:pos_left()
  self.opts.col = 1
  update_win_opts(self.win, self.opts)
  return self
end

function Window:pos_right()
  self.opts.col = self.opts.width + 2
  update_win_opts(self.win, self.opts)
  return self
end

function Window:pos_center()
  self.opts.col = math.floor((vim.o.columns - self.opts.width) / 2)
  update_win_opts(self.win, self.opts)
  return self
end

function Window:link_close(float)
  self:on_win_close(function()
    float:close()
  end)
  float:on_win_close(function()
    self:close()
  end)
  return self
end

function Window:create()
  local win = vim.api.nvim_open_win(self.buf, true, self.opts)
  self.win = win

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(self.win, true)
  end, { buffer = self.buf, noremap = true, silent = true })

  set_buf_opts(self.buf, self.buf_opts)

  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
      if tonumber(event.match) == win then
        for _, cb in ipairs(self.callbacks) do
          cb()
        end
      end
    end
  })
  return self
end

local M = {}

local function create_table_string(objects, order)
  if #objects == 0 then
    return { "No data available" }
  end

  local column_widths = {}
  for _, key in ipairs(order) do
    local max_length = #key
    for _, obj in ipairs(objects) do
      local value_length = #tostring(obj[key] or "")
      if value_length > max_length then
        max_length = value_length
      end
    end
    column_widths[key] = max_length + 5
  end

  local header = ""
  for _, key in ipairs(order) do
    header = header .. key .. string.rep(" ", column_widths[key] - #key + 2)
  end

  local separator = ""
  for _, key in ipairs(order) do
    separator = separator .. string.rep("-", column_widths[key] + 2)
  end

  local rows = {}
  for _, obj in ipairs(objects) do
    local row = ""
    for _, key in ipairs(order) do
      row = row .. tostring(obj[key] or "") .. string.rep(" ", column_widths[key] - #tostring(obj[key] or "") + 2)
    end
    table.insert(rows, row)
  end

  local result = { header, separator }
  for _, row in ipairs(rows) do
    table.insert(result, row)
  end

  return result
end

local function buffer_exists(name)
  local bufs = vim.api.nvim_list_bufs()
  for _, buf_id in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf_id) then
      local buf_name = vim.api.nvim_buf_get_name(buf_id)
      local buf_filename = vim.fn.fnamemodify(buf_name, ":t")
      if buf_filename == name then
        return buf_id
      end
    end
  end
  return nil
end

local function createStdoutBuf(name)
  local existing_buf = name == nil and nil or buffer_exists(name)
  local outBuf = existing_buf or vim.api.nvim_create_buf(true, true) -- false for not listing, true for scratch
  if existing_buf == nil and name ~= nil then
    vim.api.nvim_buf_set_name(outBuf, name)
  end
  vim.api.nvim_win_set_buf(0, outBuf)
  vim.api.nvim_set_current_buf(outBuf)
  vim.api.nvim_win_set_width(0, 30)
  vim.api.nvim_set_option_value("modifiable", false, { buf = outBuf })
  vim.api.nvim_set_option_value("filetype", "actions", { buf = outBuf })
  return {
    write = function(lines)
      vim.api.nvim_set_option_value("modifiable", true, { buf = outBuf })
      vim.api.nvim_buf_set_lines(outBuf, 0, -1, true, lines)
      vim.api.nvim_set_option_value("modifiable", false, { buf = outBuf })
    end,
    write_table = function(objects, order)
      local lines = create_table_string(objects, order)
      vim.api.nvim_set_option_value("modifiable", true, { buf = outBuf })
      vim.api.nvim_buf_set_lines(outBuf, 0, -1, true, lines)
      vim.api.nvim_set_option_value("modifiable", false, { buf = outBuf })
    end,
    bufnr = outBuf
  }
end


local function parse_gh_timestamp(dateString)
  local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z"
  local year, month, day, hour, min, sec = dateString:match(pattern)
  return os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false
  })
end

local function time_ago(timestamp)
  local unix = parse_gh_timestamp(timestamp)
  local current_time = os.time(os.date("!*t"))
  local diff = current_time - unix

  if diff < 60 then
    return string.format("%d sec ago", diff)
  elseif diff < 3600 then
    return string.format("%d min ago", math.floor(diff / 60))
  elseif diff < 86400 then
    return string.format("%d hours ago", math.floor(diff / 3600))
  else
    return string.format("%d days ago", math.floor(diff / 86400))
  end
end

local fields =
"conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,jobs,name,number,startedAt,status,updatedAt,url,workflowDatabaseId,workflowName"

local function get_job_status(status, conclusion)
  if status == "queued" then
    return "🕕"
  elseif status == "in_progress" then
    return "🔄"
  elseif conclusion == "success" then
    return "✔"
  elseif conclusion == "failure" then
    return "❌"
  elseif conclusion == "skipped" then
    return "⏩"
  else
    return "❓"
  end
end

local function get_step_status(status, conclusion)
  if status == "pending" then
    return "🕕"
  elseif status == "in_progress" then
    return "🔄"
  elseif conclusion == "success" then
    return "✔"
  elseif conclusion == "failure" then
    return "❌"
  elseif conclusion == "skipped" then
    return "⏩"
  else
    return "❓"
  end
end

local function get_workflow_status(status, conclusion)
  if status == "queued" then
    return "🕕"
  elseif status == "in_progress" then
    return "🔄"
  elseif conclusion == "success" then
    return "✔"
  elseif conclusion == "failure" then
    return "❌"
  elseif conclusion == "skipped" then
    return "⏩"
  else
    return "❓"
  end
end


local function get_job_details_lines(details)
  local lines = {}
  table.insert(lines,
    string.format("%s %s", details.displayTitle, get_workflow_status(details.status, details.conclusion)))

  table.insert(lines, "")

  table.insert(lines, string.format("Branch: %s", details.headBranch))
  table.insert(lines, string.format("Event: %s", details.event))
  if #details.conclusion > 0 then
    table.insert(lines, string.format("Finished: %s", time_ago(details.updatedAt)))
  elseif #details.startedAt > 0 then
    table.insert(lines, string.format("Started: %s", time_ago(details.startedAt)))
  end

  table.insert(lines, "")

  table.insert(lines, "Jobs:")
  for _, job in ipairs(details.jobs) do
    local jobIndent = "  "
    table.insert(lines, string.format("%sJob name: %s", jobIndent, job.name))
    table.insert(lines, string.format("%sStatus: %s", jobIndent, get_job_status(job.status, job.conclusion)))
    table.insert(lines, string.format("%sSteps: %s", jobIndent, ""))

    for i, step in ipairs(job.steps) do
      local stepIndent = jobIndent .. "       "
      table.insert(lines,
        string.format("%s%d. %s %s", stepIndent, i, step.name, get_step_status(step.status, step.conclusion)))
      if i ~= #job.steps then
        table.insert(lines, "")
      end
    end
  end

  return lines
end


local function job_stderr_float(id, float)
  local lines = {}

  local stderr_float = Window.new_float():pos_right():on_win_close(function()
    float:pos_center()
  end):create():write_buf({ "Loading stacktrace" })
  float:pos_left()

  vim.fn.jobstart(string.format("gh run view %s --log-failed", id), {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        local pattern = "^(.-)%s+([%d%-:T%.Z]+)%s+(.*)$"
        local job_name, timestamp, stderr = line:match(pattern)
        if job_name == nil then
          return
        end
        table.insert(lines, {
          job_name = job_name,
          timestamp = timestamp,
          stderr = stderr
        })
      end
    end,
    on_exit = function()
      float:on_win_close(function()
        if vim.api.nvim_win_is_valid(stderr_float.win) then
          vim.api.nvim_win_close(stderr_float.win, true)
        end
      end)

      local buf_lines = {}
      for _, value in ipairs(lines) do
        table.insert(buf_lines, string.format("%s: %s", value.job_name, value.stderr))
      end
      stderr_float:write_buf(buf_lines)

      for line_index, value in ipairs(lines) do
        vim.api.nvim_buf_add_highlight(stderr_float.buf, require("octo.constants").OCTO_WORKFLOW_NS, "ErrorMsg",
          line_index - 1,
          #value.job_name + 2, -1)
      end
    end
  })
end

local function update_job_details(id, float)
  local win = float.win
  local buf = float.buf

  local job_details = {}
  vim.fn.jobstart(string.format("gh run view %s --json %s", id, fields), {
    stdout_buffered = true,
    on_stdout = function(_, data)
      job_details = vim.fn.json_decode(table.concat(data, "\n"))
    end,
    on_exit = function(_, b)
      if b == 0 then
        float:write_buf(get_job_details_lines(job_details))

        vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Question", 0, 0, -1)
        vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 2, 0, -1)
        vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 3, 0, -1)
        vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 4, 0, -1)

        if job_details.conclusion == "failure" then
          job_stderr_float(id, float)
        end

        if #job_details.conclusion == 0 then
          local function refresh_job_details()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) then
              update_job_details(id, float)
            end
          end
          vim.defer_fn(refresh_job_details, 5000)
          vim.api.nvim_buf_set_extmark(buf, require("octo.constants").OCTO_WORKFLOW_NS, 0, 0, {
            virt_text = { { string.format("auto refresh enabled"), "Character" } },
            virt_text_pos = "right_align",
            priority = 200,
          })
        end
      else
        --stderr
      end
    end
  })
end

local function job_details_float(id)
  local float = Window.new_float()
      :create()
      :write_buf({ "Loading job run.." })
  update_job_details(id, float)
end

local function populate_list(buf)
  local lines = {}
  vim.fn.jobstart("gh run list --json conclusion,displayTitle,event,headBranch,name,number,status,updatedAt,databaseId",
    {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local json = vim.fn.json_decode(table.concat(data))
        for _, value in ipairs(json) do
          local wf_run = {
            status = value.status == "queued" and "🕐" or value.status == "in_progress" and "🔁" or
                value.conclusion == "failure" and "❌" or "✅",
            title = value.displayTitle,
            branch = value.headBranch,
            name = value.name,
            age = time_ago(value.updatedAt),
            id = value.databaseId
          }
          table.insert(lines, wf_run)
        end
      end,
      on_exit = function()
        local mapping = require("octo.config").values.mappings.run.open.lhs
        vim.keymap.set('n', mapping, function()
          local line_num = vim.api.nvim_win_get_cursor(0)[1]
          local line = lines[line_num - 2]
          if line == nil then
            return
          end
          job_details_float(line.id)
        end, { buffer = buf.bufnr, noremap = true, silent = true })

        local order = { "status", "title", "branch", "name", "age" }
        buf.write_table(lines, order)
        local ns_id = require("octo.constants").OCTO_WORKFLOW_NS
        vim.api.nvim_buf_set_extmark(buf.bufnr, ns_id, 0, 0, {
          virt_text = { { string.format("auto refresh enabled"), "Character" } },
          virt_text_pos = "right_align",
          priority = 200,
        })
      end
    })
end


M.list = function()
  local buf_name = "Workflow runs"
  local buf = createStdoutBuf(buf_name)
  local focused = true
  populate_list(buf)

  local function refresh()
    if focused == false then
      return
    end
    populate_list(buf)
    vim.defer_fn(refresh, 30000)
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    buffer = buf.bufnr,
    callback = function()
      focused = true
      refresh()
    end
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
    buffer = buf.bufnr,
    callback = function()
      focused = false
    end
  })

  refresh()

  local mapping = require("octo.config").values.mappings.run.refresh.lhs
  vim.keymap.set('n', mapping, function()
    vim.notify("Refreshing")
    populate_list(buf)
  end, { buffer = buf.bufnr, noremap = true, silent = true })

  buf.write({ "Loading actions..." })
end

return M
