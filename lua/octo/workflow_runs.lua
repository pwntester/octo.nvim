---@alias LineType "step" | "step_log" | "job" | "separator" | nil

---@class LineDef
---@field value string
---@field id string | nil
---@field type LineType
---@field highlight string | nil
---@field step_log LineDef[] | nil
---@field expanded boolean | nil


local M = {
  buf = nil,
  buf_name = "",
  filetype = "",
  lines = {},
  current_wf = nil,
  current_wf_log = nil
}
local namespace = require("octo.constants").OCTO_WORKFLOW_NS


local function match_lines_to_names(names, lines)
  local results = {}
  local name_index = 1

  for _, line in ipairs(lines) do
    -- Match the current line with the current name
    local current_name = names[name_index]
    local next_name = names[name_index + 1]

    if line:find(current_name, 1, true) then
      table.insert(results, { line = line, matched_name = current_name })
    elseif next_name ~= nil and line:find(next_name, 1, true) then
      table.insert(results, { line = line, matched_name = next_name })
      name_index = name_index + 1
    else
      error("Failed to match line to step: " .. line)
    end
  end

  return results
end

local function split_by_newline(input)
  local result = {}
  for line in input:gmatch("([^\n]*)\n?") do
    if line ~= "" then
      table.insert(result, line)
    end
  end
  return result
end



local function extractAfterTimestamp(logLine)
  local result = logLine:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s*(.*)")
  return result
end

local function get_logs(id)
  for _, value in ipairs(M.lines) do
    -- value.expanded = false
    value.step_log = {}
  end
  --TODO: check if logs are "fresh"
  local out = vim.system(
    {
      "gh",
      "run",
      "view",
      id,
      "--log"
    }):wait()

  local stdout = out.stdout
  local names = {}
  --TODO: multi job support
  local currJob = M.current_wf.jobs[1]
  for _, value in ipairs(currJob.steps) do
    table.insert(names, value.name)
  end

  local matches = match_lines_to_names(names, split_by_newline(stdout))

  for _, log_entry in ipairs(matches) do
    for _, line in ipairs(M.lines) do
      if line.id == log_entry.matched_name then
        line.step_log = line.step_log or {}
        table.insert(line.step_log, { value = extractAfterTimestamp(log_entry.line), highlight = "Question" })
        print("Inserted line")
      end
    end
  end
end

local keymaps = {
  ---@param line LineDef
  ["<CR>"] = function(line)
    if line.type == "step" then
      if line.expanded == true then
        line.expanded = false
      else
        -- print(vim.inspect(M.current_wf))
        get_logs(M.current_wf.databaseId)
        -- line.step_log = {
        --   { value = "Failed to load stuff",        type = "step_log" },
        --   { value = "And other interesting stuff", type = "step_log" },
        -- }
        line.expanded = true
      end
    end
    M.refresh()
  end
}


local fields =
"conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,jobs,name,number,startedAt,status,updatedAt,url,workflowDatabaseId,workflowName"

local function get_job_status(status, conclusion)
  local icons = require("octo.config").values.runs.icons
  if status == "queued" then
    return icons.skipped
  elseif status == "in_progress" then
    return icons.in_progress
  elseif conclusion == "success" then
    return icons.succeeded
  elseif conclusion == "failure" then
    return icons.failed
  elseif conclusion == "skipped" then
    return icons.skipped
  else
    return "❓"
  end
end

local function get_step_status(status, conclusion)
  local icons = require("octo.config").values.runs.icons
  if status == "pending" then
    return icons.pending
  elseif status == "in_progress" then
    return icons.in_progress
  elseif conclusion == "success" then
    return icons.succeeded
  elseif conclusion == "failure" then
    return icons.failed
  elseif conclusion == "skipped" then
    return icons.skipped
  else
    return "❓"
  end
end

local function get_workflow_status(status, conclusion)
  local icons = require("octo.config").values.runs.icons
  if status == "queued" then
    return icons.pending
  elseif status == "in_progress" then
    return icons.in_progress
  elseif conclusion == "success" then
    return icons.succeeded
  elseif conclusion == "failure" then
    return icons.failed
  elseif conclusion == "skipped" then
    return icons.skipped
  else
    return "❓"
  end
end
local utils = require "octo.utils"
local actions = require('telescope.actions')

---@type LineDef
local separator = {
  value = "",
  highlight = nil,
  id = "",
  type = "separator"
}

local function get_job_details_lines(details)
  ---@type LineDef[]
  local lines = {}
  table.insert(lines,
    {
      value = string.format("%s %s", details.displayTitle, get_workflow_status(details.status, details.conclusion)),
      highlight = "Question"
    })

  table.insert(lines, separator)

  table.insert(lines, { value = string.format("Branch: %s", details.headBranch), highlight = "Directory" })
  table.insert(lines, { value = string.format("Event: %s", details.event), highlight = "Directory" })

  if #details.conclusion > 0 then
    table.insert(lines,
      { value = string.format("Finished: %s", utils.format_date(details.updatedAt)), highlight = "Directory" })
  elseif #details.startedAt > 0 then
    table.insert(lines,
      { value = string.format("Started: %s", utils.format_date(details.startedAt)), highlight = "Directory" })
  end

  table.insert(lines, separator)

  table.insert(lines, { value = "Jobs:" })
  for _, job in ipairs(details.jobs) do
    local jobIndent = "  "
    table.insert(lines, { value = string.format("%sJob name: %s", jobIndent, job.name), id = job.name, type = "job" })
    table.insert(lines, { value = string.format("%sStatus: %s", jobIndent, get_job_status(job.status, job.conclusion)) })
    table.insert(lines, { value = string.format("%sSteps: %s", jobIndent, "") })

    for i, step in ipairs(job.steps) do
      local stepIndent = jobIndent .. "       "
      table.insert(
        lines,
        {
          value = string.format("%s%d. %s %s", stepIndent, i, step.name, get_step_status(step.status, step.conclusion)),
          id = step.name,
          type = "step"
        }
      )
      if i ~= #job.steps then
        table.insert(lines, separator)
      end
    end
    table.insert(lines, separator)
  end

  return lines
end



local wf_cache = {}
local function update_job_details(id, buf)
  local job_details = {}
  vim.fn.jobstart(string.format("gh run view %s --json %s", id, fields), {
    stdout_buffered = true,
    on_stdout = function(_, data)
      job_details = vim.fn.json_decode(table.concat(data, "\n"))
      wf_cache[id] = job_details
      M.current_wf = job_details
    end,
    on_exit = function(_, b)
      if b == 0 then
        local lines = get_job_details_lines(job_details)
        if vim.api.nvim_buf_is_valid(buf) then
          M.lines = lines
          M.refresh()
        end

        if #job_details.conclusion == 0 then
          local function refresh_job_details()
            if vim.api.nvim_buf_is_valid(buf) then
              update_job_details(id, buf)
            end
          end
          vim.defer_fn(refresh_job_details, 5000)
          vim.api.nvim_buf_set_extmark(buf, require("octo.constants").OCTO_WORKFLOW_NS, 0, 0, {
            virt_text = { { string.format "auto refresh enabled", "Character" } },
            virt_text_pos = "right_align",
            priority = 200,
          })
        end
      else
        --stderr
      end
    end,
  })
end

local function populate_preview_buffer(id, buf)
  --TODO: check outcome and if running refresh otherwise cached value is valid
  if wf_cache[id] ~= nil and vim.api.nvim_buf_is_valid(buf) then
    local lines = get_job_details_lines(wf_cache[id])
    M.lines = lines
    M.refresh()
  end
  update_job_details(id, buf)
  M.refresh()
end

local function print_lines()
  vim.api.nvim_buf_clear_namespace(M.buf, namespace, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local lines = {}
  local highlights = {}

  for _, line_def in ipairs(M.lines) do
    table.insert(lines, line_def.value)
    table.insert(highlights, { index = #lines - 1, highlight = line_def.highlight })
    if next(line_def.step_log or {}) and line_def.expanded then
      for _, log_line in ipairs(line_def.step_log) do
        local stringified = string.rep(" ", 11) .. log_line.value
        table.insert(lines, stringified)
        table.insert(highlights, { index = #lines - 1, highlight = log_line.highlight })
      end
    end
  end


  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

  for _, value in ipairs(highlights) do
    if value.highlight then
      vim.api.nvim_buf_add_highlight(M.buf, namespace, value.highlight, value.index, 0, -1)
    end
  end


  -- apply_highlights()
end

M.refresh = function()
  print_lines()
end

local function get_workflow_runs_sync(co)
  local icons = require("octo.config").values.runs.icons
  local lines = {}
  vim.fn.jobstart(
    "gh run list --json conclusion,displayTitle,event,headBranch,name,number,status,updatedAt,databaseId",
    {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local json = vim.fn.json_decode(table.concat(data))
        for _, value in ipairs(json) do
          local wf_run = {
            status = value.status == "queued" and icons.pending
                or value.status == "in_progress" and icons.in_progress
                or value.conclusion == "failure" and icons.failed
                or icons.succeeded,
            title = value.displayTitle,
            display = value.displayTitle,
            value = value.databaseId,
            branch = value.headBranch,
            name = value.name,
            age = utils.format_date(value.updatedAt),
            id = value.databaseId,
          }
          table.insert(lines, wf_run)
        end
      end,
      on_exit = function()
        coroutine.resume(co)
      end,
    }
  )
  coroutine.yield()
  return lines
end

local preview_picker = function(bufnr, options, on_select_cb, title, previewer)
  if #options == 0 then
    error "No options provided, minimum 1 is required"
  end

  -- Auto pick if only one option present
  if #options == 1 then
    on_select_cb(options[1])
    return
  end

  local previewers = require "telescope.previewers"
  local picker = require("telescope.pickers").new(bufnr, {
    prompt_title = title,
    finder = require("telescope.finders").new_table {
      results = options,
      entry_maker = function(entry)
        return {
          display = entry.display,
          value = entry,
          ordinal = entry.display,
        }
      end,
    },
    previewer = previewers.new_buffer_previewer {
      title = title .. " preview",
      define_preview = previewer,
    },
    sorter = require("telescope.config").values.generic_sorter {},
    preview = true,
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "q", function(prompt_bufnr)
        require("telescope.actions").close(prompt_bufnr)
      end)
      return true
    end,
  })
  picker:find()
end


---@class LogEntry
---@field line string
---@field step_name string




local function table_to_string(tbl, indent)
  if not indent then indent = 0 end
  local str = ""
  for k, v in pairs(tbl) do
    local key = tostring(k)
    if type(v) == "table" then
      str = str .. string.rep(" ", indent) .. key .. ":\n" .. table_to_string(v, indent + 2)
    else
      str = str .. string.rep(" ", indent) .. key .. ": " .. tostring(v) .. "\n"
    end
  end
  return str
end

local write_to_log = function(message)
  local log_path = os.tmpname()
  -- Open the file in append mode
  local file, err = vim.loop.fs_open(log_path, "a", 438) -- 438 is the octal value for file permissions 0666

  if err then
    print("Error opening file: " .. err)
    return
  end

  -- Write the message to the file
  if (type(message) == "table") then
    vim.loop.fs_write(file, table_to_string(message) .. "\n", -1)
  elseif type(message) == "string" then
    vim.loop.fs_write(file, message .. "\n", -1)
  else
    error("Failed to write to log, datatype: " .. type(message) .. " not supported")
  end

  -- Close the file
  vim.loop.fs_close(file)
  return log_path
end

local function render(selected)
  local new_buf = vim.api.nvim_create_buf(true, true)
  M.buf = new_buf
  vim.api.nvim_set_current_buf(new_buf)
  populate_preview_buffer(selected.id, new_buf)
  vim.api.nvim_buf_set_name(new_buf, "" .. selected.id)

  for binding, cb in pairs(keymaps) do
    vim.keymap.set("n", binding, function()
      local index = 1
      local current_line = vim.api.nvim_win_get_cursor(0)[1]

      for _, value in ipairs(M.lines) do
        if current_line == index then
          cb(value)
        end
        index = index + 1
        if next(value.step_log or {}) and value.expanded == true then
          for _, step_log in ipairs(value.step_log) do
            if current_line == index then
              cb(step_log)
            end
            index = index + 1
          end
        end
      end
    end)
  end

  -- vim.keymap.set("n", "<CR>", function()
  --   if wf_cache[selected.id] and false then
  --     local workflow = wf_cache[selected.id]
  --
  --     local names = {}
  --     local currJob = workflow.jobs[1]
  --     for _, value in ipairs(currJob.steps) do
  --       table.insert(names, value.name)
  --     end
  --     print(vim.inspect(names))
  --
  --     vim.notify("I should open this line")
  --     print(vim.inspect(matches))
  --     local file = write_to_log(matches)
  --   else
  --     local current_line = vim.api.nvim_win_get_cursor(0)[1]
  --     print("Workflow has not loaded yet")
  --   end
  -- end, { noremap = true, silent = true, buffer = new_buf })
end


M.list = function()
  vim.notify "Fetching workflow runs (this may take a while) ..."
  local co = coroutine.running()
  local wf_runs = get_workflow_runs_sync(co)

  preview_picker(
    nil,
    wf_runs,
    function(selected)
      render(selected)
    end,
    "Workflow runs",
    function(self, entry)
      local id = entry.value.id
      M.buf = self.state.bufnr
      populate_preview_buffer(id, self.state.bufnr)
    end
  )
end

return M
