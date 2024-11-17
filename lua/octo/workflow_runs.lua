---@alias LineType "job" | "step" | "step_log" |  nil

---@class WorkflowRun
---@field conclusion string
---@field createdAt string
---@field databaseId string
---@field displayTitle string
---@field event string
---@field headBranch string
---@field headSha string
---@field name string
---@field number number
---@field startedAt string
---@field status string
---@field updatedAt string
---@field url string
---@field workflowDatabaseId string
---@field workflowName string
---@field jobs WorkflowJob[]

---@class WorkflowJob
---@field completedAt string
---@field conclusion string
---@field databaseId number
---@field name string
---@field startedAt string
---@field status string
---@field steps WorkflowStep[]
---@field url string

---@class WorkflowStep
---@field conclusion string
---@field name string
---@field number number
---@field status string


---@class LineDef
---@field value string
---@field id string | nil
---@field highlight string | nil
---@field node_ref WorkflowNode | nil


---@class Handler
---@field tree table<string,WorkflowNode>
---@field buf_name string
---@field filetype string
---@field current_wf WorkflowRun
---@field current_wf_log table

---@class WorkflowNode
---@field id string
---@field display string
---@field type LineType
---@field job_id string
---@field indent number
---@field expanded boolean
---@field highlight string
---@field preIcon string
---@field icon string
---@field children table<string, WorkflowNode>


local M = {
  buf = nil,
  buf_name = "",
  filetype = "",
  lines = {},
  tree = {},
  current_wf = nil,
  current_wf_log = nil,
  wf_cache = {}
}

local namespace = require("octo.constants").OCTO_WORKFLOW_NS


---@param data WorkflowRun
---@return WorkflowNode
local function generateWorkflowTree(data)
  local root = {
    id = "Jobs",
    display = "Jobs",
    type = "root",
    job_id = "",
    indent = 0,
    expanded = true,
    highlight = nil,
    preIcon = "",
    icon = "📂",
    children = {}
  }

  for _, job in ipairs(data.jobs) do
    local jobNode = {
      id = job.name,
      job_id = job.name,
      display = job.name,
      type = "job",
      indent = 2,
      expanded = true,
      highlight = nil,
      preIcon = "",
      icon = "🛠️",
      children = {}
    }

    for _, step in ipairs(job.steps) do
      local stepNode = {
        id = step.name,
        job_id = jobNode.id,
        display = step.name,
        type = "step",
        indent = 4,
        expanded = false,
        highlight = nil,
        preIcon = "",
        icon = "",
        children = {}
      }
      table.insert(jobNode.children, stepNode)
    end

    table.insert(root.children, jobNode)
  end

  return root
end

local function extractAfterTimestamp(logLine)
  local result = logLine:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s*(.*)")
  return result
end

---@param names JobStep[]
---@param lines string[]
local function match_lines_to_names(names, lines)
  local results = {}
  local name_index = 1

  for _, line in ipairs(lines) do
    local current_name = names[name_index]
    local next_name = names[name_index + 1]

    local job_results = results[current_name.job]
    if not job_results then
      job_results = {}
      results[current_name.job] = job_results
    end

    if line:find(current_name.job, 1, true) and line:find(current_name.step, 1, true) then
      table.insert(job_results,
        { line = line, job = current_name.job, step = current_name.step })
    elseif next_name and line:find(next_name.job, 1, true) and line:find(next_name.step, 1, true) then
      name_index = name_index + 1
      local next_job_results = results[next_name.job]
      if not next_job_results then
        next_job_results = {}
        results[next_name.job] = next_job_results
      end
      table.insert(next_job_results,
        { line = line, job = next_name.job, step = next_name.step })
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

---Traverses a tree from the given node, giving a callback for every item
---@param tree WorkflowNode | nil
---@param cb function
M.traverse = function(tree, cb)
  if not tree then
    tree = M.tree
  end
  --HACK: handle no tree set
  if not tree.id then
    return
  end

  cb(tree)
  for _, node in ipairs(tree.children or {}) do
    M.traverse(node, cb)
  end
end


---@class JobStep
---@field job string
---@field step string


local function collapse_groups(lines)
  local collapsed = {}
  local current_group = nil

  for _, line in ipairs(lines) do
    if extractAfterTimestamp(line):find("##%[group%]") then
      -- Start a new group
      current_group = { line }
    elseif extractAfterTimestamp(line):find("##%[endgroup%]") then
      if current_group then
        -- End the current group and collapse it
        table.insert(collapsed, table.concat(current_group, "\n"))
        current_group = nil
      else
        error("Mismatched ##[endgroup] found: " .. line)
      end
    elseif current_group then
      -- Add to the current group
      table.insert(current_group, line)
    else
      -- Regular line, add directly
      table.insert(collapsed, line)
    end
  end

  -- Error if a group is left open
  if current_group then
    error("Unclosed group found.")
  end

  return collapsed
end


local function create_log_child(value, indent)
  return {
    display = extractAfterTimestamp(value)
        :gsub("##%[group%]", "> ")
        :gsub("##%[endgroup%]", "")
        :gsub("%[command%]", ""),
    id = value,
    expanded = false,
    indent = indent + 2,
    type = "step_log",
    highlight = value:find("%[command%]") ~= nil and "PreProc" or "Question",
    icon = "",
    preIcon = "",
    children = {},
  }
end



local function get_logs(id)
  ---@type JobStep[]
  local names = {}
  ---@param node WorkflowNode
  M.traverse(M.tree, function(node)
    if node.type == "step" then
      table.insert(names, { step = node.id, job = node.job_id })
    end
  end)

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

  --TODO: convert tree from pairs to ipairs due to bug in sequencing
  local matches = match_lines_to_names(names, collapse_groups(split_by_newline(stdout)))

  --clear all children
  M.traverse(M.tree, function(i)
    if i.type ~= "step" then
      return
    end
    i.children = {}
  end)


  for job, entry in pairs(matches) do
    for _, log_entry in ipairs(entry) do
      ---@param node WorkflowNode
      M.traverse(M.tree, function(node)
        if node.type ~= "step" or node.job_id ~= job then
          return
        end
        if node.id == log_entry.step then
          local lines = split_by_newline(log_entry.line)
          local log_child = create_log_child(lines[1], node.indent)
          if #lines > 1 then
            local sub = {}
            for i, value in ipairs(lines) do
              if i ~= 1 then
                table.insert(sub, create_log_child(value, log_child.indent))
              end
            end
            log_child.children = sub
          end
          table.insert(node.children, log_child)
        end
      end)
    end
  end
end

local tree_keymaps = {
  ---@param node WorkflowNode
  ["<CR>"] = function(node)
    if node.expanded == false then
      node.expanded = true
      if node.type == "step" then
        get_logs(M.current_wf.databaseId)
      end
    else
      node.expanded = false
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

local function get_workflow_header()
  ---@type WorkflowRun
  local details = M.current_wf
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


  return lines
end



local function update_job_details(id, buf)
  ---@type WorkflowRun
  local job_details = {}
  if M.wf_cache[id] ~= nil then
    M.refresh()
    return
  end
  vim.fn.jobstart(string.format("gh run view %s --json %s", id, fields), {
    stdout_buffered = true,
    on_stdout = function(_, data)
      job_details = vim.fn.json_decode(table.concat(data, "\n"))
      M.wf_cache[id] = job_details
    end,
    on_exit = function(_, b)
      if b == 0 then
        M.current_wf = job_details
        M.tree = generateWorkflowTree(job_details)
        M.refresh()
        -- local lines = get_job_details_lines(job_details)
        -- if vim.api.nvim_buf_is_valid(buf) then
        --   M.lines = lines
        --   M.refresh()
        -- end
        --
        -- if #job_details.conclusion == 0 then
        --   local function refresh_job_details()
        --     if vim.api.nvim_buf_is_valid(buf) then
        --       update_job_details(id, buf)
        --     end
        --   end
        --   vim.defer_fn(refresh_job_details, 5000)
        --   vim.api.nvim_buf_set_extmark(buf, require("octo.constants").OCTO_WORKFLOW_NS, 0, 0, {
        --     virt_text = { { string.format "auto refresh enabled", "Character" } },
        --     virt_text_pos = "right_align",
        --     priority = 200,
        --   })
        -- end
      else
        print("Failed to get workflow run for " .. id)
        --stderr
      end
    end,
  })
end

local function populate_preview_buffer(id, buf)
  local cached = M.wf_cache[id]
  --TODO: check outcome and if running refresh otherwise cached value is valid
  if cached and vim.api.nvim_buf_is_valid(buf) then
    M.current_wf = cached
    M.tree = generateWorkflowTree(cached)
    M.refresh()
  else
    update_job_details(id, buf)
  end
end


---@param node WorkflowNode
---@return string
local function format_node(node)
  local indent = string.rep(" ", node.indent)
  local preIcon = node.type ~= "step_log" and (node.expanded == true and "> " or "> ") or ""
  local formatted = string.format("%s%s%s", indent, preIcon, node.display)
  return formatted
end

---@param node WorkflowNode
---@param list LineDef[] | nil
---@return LineDef[]
local function tree_to_string(node, list)
  list = list or {}
  local formatted = format_node(node)
  ---@type LineDef
  local lineDef = {
    value = formatted,
    id = node.id,
    type = node.type,
    highlight = node.highlight or nil,
    step_log = nil,
    expanded = node.expanded or false,
    node_ref = node
  }

  table.insert(list, lineDef)
  if node.type ~= "step_log" then
    table.insert(list, separator)
  end

  if node.expanded and next(node.children) then
    for _, child in ipairs(node.children) do
      tree_to_string(child, list)
    end
  end

  return list
end


local function print_lines()
  vim.api.nvim_buf_clear_namespace(M.buf, namespace, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)


  local lines = get_workflow_header()
  ---Offset is first x before tree
  local offset = #lines

  local stringified_tree = tree_to_string(M.tree, {})
  for _, value in ipairs(stringified_tree) do
    table.insert(lines, value)
  end

  local highlights = {}

  local string_lines = {}

  for index, line_def in ipairs(lines) do
    table.insert(string_lines, line_def.value)
    table.insert(highlights, { index = index - 1, highlight = line_def.highlight })
  end


  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, string_lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

  for _, vl in ipairs(highlights) do
    if vl.highlight then
      vim.api.nvim_buf_add_highlight(M.buf, namespace, vl.highlight, vl.index, 0, -1)
    end
  end


  for binding, cb in pairs(tree_keymaps) do
    vim.keymap.set("n", binding, function()
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      local line = lines[current_line]
      if line.node_ref ~= nil then
        cb(line.node_ref)
      end
    end)
  end
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


local function render(selected)
  local new_buf = vim.api.nvim_create_buf(true, true)
  M.buf = new_buf
  vim.api.nvim_set_current_buf(new_buf)
  populate_preview_buffer(selected.id, new_buf)
  vim.api.nvim_buf_set_name(new_buf, "" .. selected.id)
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
