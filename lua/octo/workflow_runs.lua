local namespace = require("octo.constants").OCTO_WORKFLOW_NS
local mappings = require("octo.config").values.mappings.runs
local icons = require("octo.config").values.runs.icons
local navigation = require "octo.navigation"
local utils = require "octo.utils"
local previewers = require "telescope.previewers"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local actions = require "telescope.actions"
local state = require "telescope.actions.state"
local config = require "telescope.config"
local octo_error = require("octo.utils").error

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
---@field buf integer
---@field filetype string
---@field current_wf WorkflowRun
---@field wf_cache table<string,WorkflowRun>
---@field refresh function
---@field refetch function

---@class WorkflowNode
---@field id string
---@field display string
---@field type LineType
---@field job_id string
---@field indent number
---@field expanded boolean
---@field number number | nil
---@field highlight string | nil
---@field preIcon string
---@field icon string
---@field status string
---@field conclusion string
---@field children table<string, WorkflowNode>

local M = {
  buf = nil,
  buf_name = "",
  filetype = "",
  tree = {},
  current_wf = nil,
  wf_cache = {},
}

local function get_repo_name()
  local result = vim.system({ "gh", "repo", "view", "--json", "nameWithOwner" }, { text = true }):wait()

  if result.code ~= 0 then
    error("Failed to execute 'gh repo view': " .. (result.stderr or "Unknown error"))
  end

  local ok, decoded = pcall(vim.json.decode, result.stdout)
  if not ok or not decoded or not decoded.nameWithOwner then
    error "Failed to parse repository name from 'gh repo view' output"
  end

  return decoded.nameWithOwner
end

---@return string | nil
local function get_job_highlight(status, conclusion)
  if status == "queued" then
    return "Question"
  elseif status == "in_progress" then
    return "Directory"
  elseif conclusion == "success" then
    return "Character"
  elseif conclusion == "failure" then
    return "ErrorMsg"
  elseif conclusion == "skipped" then
    return "NonText"
  elseif conclusion == "cancelled" then
    return "NonText"
  end
end

---@return string | nil
local function get_step_highlight(status, conclusion)
  if status == "pending" then
    return "Question"
  elseif status == "in_progress" then
    return "Directory"
  elseif conclusion == "success" then
    return "Character"
  elseif conclusion == "failure" then
    return "ErrorMsg"
  elseif conclusion == "skipped" then
    return "NonText"
  elseif conclusion == "cancelled" then
    return "NonText"
  end
end

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
    children = {},
  }

  for _, job in ipairs(data.jobs) do
    local jobNode = {
      id = job.name,
      job_id = job.name,
      display = job.name,
      type = "job",
      indent = 2,
      expanded = true,
      highlight = get_job_highlight(job.status, job.conclusion),
      status = job.status,
      conclusion = job.conclusion,
      preIcon = "",
      icon = "🛠️",
      children = {},
    }

    for _, step in ipairs(job.steps) do
      ---@type WorkflowNode
      local stepNode = {
        id = step.name,
        job_id = jobNode.id,
        display = step.name,
        status = step.status,
        number = step.number,
        conclusion = step.conclusion,
        type = "step",
        indent = 4,
        expanded = false,
        highlight = get_step_highlight(step.status, step.conclusion),
        preIcon = "",
        icon = "",
        children = {},
      }
      table.insert(jobNode.children, stepNode)
    end

    table.insert(root.children, jobNode)
  end

  return root
end

local function extractAfterTimestamp(logLine)
  local result = logLine:match "%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s*(.*)"
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

local function collapse_groups(lines)
  local collapsed = {}
  local current_group = nil

  for _, line in ipairs(lines) do
    if extractAfterTimestamp(line):find "##%[group%]" then
      current_group = { line }
    elseif extractAfterTimestamp(line):find "##%[endgroup%]" then
      if current_group then
        table.insert(collapsed, table.concat(current_group, "\n"))
        current_group = nil
      else
        error("Mismatched ##[endgroup] found: " .. line)
      end
    elseif current_group then
      table.insert(current_group, line)
    else
      table.insert(collapsed, line)
    end
  end

  if current_group then
    error "Unclosed group found."
  end

  return collapsed
end

local function create_log_child(value, indent)
  return {
    display = extractAfterTimestamp(value)
      :gsub("##%[group%]", "> ")
      :gsub("##%[endgroup%]", "")
      :gsub("%[command%]", "")
      :gsub("##%[warning%]", "Warning: ")
      :gsub("##%[notice%]", "Notice: ")
      --strip ansi color codes
      :gsub("\x1b%[[%d;]*m", ""),
    id = value,
    expanded = false,
    indent = indent + 2,
    type = "step_log",
    highlight = value:find "%[command%]" ~= nil and "PreProc" or "Question",
    icon = "",
    preIcon = "",
    children = {},
  }
end

-- Accepts zip contents and writes and then unzips them
---@param stdout string - The zip content to write
local function write_and_unzip_file(stdout)
  local temp_location = os.tmpname()
  local zip_location = temp_location .. ".zip"
  local file = io.open(zip_location, "wb")
  if not file then
    octo_error "Failed to create temporary file"
    return
  end

  file:write(stdout)
  file:close()

  local unzipOutput = vim.system({ "unzip", "-d", temp_location, zip_location }):wait()

  if unzipOutput.code ~= 0 then
    octo_error("Failed to unzip logs: " .. (unzipOutput.stderr or "Unknown error"))
  end

  local success, err = pcall(function()
    vim.loop.fs_unlink(zip_location)
  end)

  if not success then
    octo_error("Error deleting zip archive: " .. err)
  end

  return temp_location
  --TODO: return handler for deleting file
end

local function get_logs(id)
  --TODO: check if logs are "fresh"
  local reponame = get_repo_name()
  local out = vim
    .system({
      "gh",
      "api",
      string.format("repos/%s/actions/runs/%s/logs", reponame, id, 0),
    })
    :wait()

  if out.code ~= 0 then
    octo_error("Failed to fetch logs: " .. (out.stderr or "Unknown error"))
    return
  end

  local temp_location = write_and_unzip_file(out.stdout)

  ---@param node WorkflowNode
  M.traverse(M.tree, function(node)
    if node.type ~= "step" then
      return
    end

    local sanitized_name = node.id:gsub("/", "")
    local file_name = string.format("%s_%s.txt", node.number, sanitized_name)
    local path = vim.fs.normalize(vim.fs.joinpath(temp_location, node.job_id, file_name))
    local lines = vim.fn.readfile(path)

    node.children = {}

    for _, collapsed in ipairs(collapse_groups(lines)) do
      local groupedLines = vim.fn.split(collapsed, "\n")
      local log_child = create_log_child(groupedLines[1], node.indent)
      if #groupedLines > 1 then
        local sub = {}
        for i, value in ipairs(groupedLines) do
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

local keymaps = {
  ---@param api Handler
  [mappings.refresh.lhs] = function(api)
    vim.notify "refreshing..."
    api.refetch()
  end,
  [mappings.open_in_browser.lhs] = function(api)
    local id = api.current_wf.databaseId
    navigation.open_in_browser("workflow_run", nil, id)
  end,
}

local tree_keymaps = {
  ---@param node WorkflowNode
  [mappings.expand_step.lhs] = function(node)
    if node.expanded == false then
      node.expanded = true
      if node.type == "step" then
        -- only refresh logs aggressively if step is in_progress
        if (not next(node.children)) or node.conclusion == "in_progress" then
          get_logs(M.current_wf.databaseId)
        end
      end
    else
      node.expanded = false
    end
    M.refresh()
  end,
}

local fields =
  "conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,jobs,name,number,startedAt,status,updatedAt,url,workflowDatabaseId,workflowName"

local function get_job_status(status, conclusion)
  if status == "queued" then
    return icons.skipped
  elseif status == "in_progress" then
    return icons.in_progress
  elseif conclusion == "success" then
    return ""
  elseif conclusion == "failure" then
    return icons.failed
  elseif conclusion == "skipped" then
    return icons.skipped
  elseif conclusion == "cancelled" then
    return icons.cancelled
  else
    return "❓"
  end
end

local function get_step_status(status, conclusion)
  if status == "pending" then
    return icons.pending
  elseif status == "in_progress" then
    return icons.in_progress
  elseif conclusion == "success" then
    return ""
  elseif conclusion == "failure" then
    return icons.failed
  elseif conclusion == "skipped" then
    return icons.skipped
  elseif conclusion == "cancelled" then
    return icons.cancelled
  else
    return "❓"
  end
end

local function get_workflow_status(status, conclusion)
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

---@type LineDef
local separator = {
  value = "",
  highlight = nil,
  id = "",
  type = "separator",
}

local function get_workflow_header()
  ---@type WorkflowRun
  local details = M.current_wf
  ---@type LineDef[]
  local lines = {}
  table.insert(lines, {
    value = string.format("%s %s", details.displayTitle, get_workflow_status(details.status, details.conclusion)),
    highlight = "Question",
  })

  table.insert(lines, separator)

  table.insert(lines, { value = string.format("Branch: %s", details.headBranch), highlight = "Directory" })
  table.insert(lines, { value = string.format("Event: %s", details.event), highlight = "Directory" })

  if #details.conclusion > 0 then
    table.insert(
      lines,
      { value = string.format("Finished: %s", utils.format_date(details.updatedAt)), highlight = "Directory" }
    )
  elseif #details.startedAt > 0 then
    table.insert(
      lines,
      { value = string.format("Started: %s", utils.format_date(details.startedAt)), highlight = "Directory" }
    )
  end

  table.insert(lines, separator)
  return lines
end

local function update_job_details(id)
  ---@type WorkflowRun
  local job_details = {}
  if M.wf_cache[id] ~= nil then
    M.refresh()
    return
  end
  local cmd = string.format("gh run view %s --json %s", id, fields)
  vim.fn.jobstart(cmd, {
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
      else
        octo_error("Failed to get workflow run for " .. id)
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
    update_job_details(id)
  end
end

---@param node WorkflowNode
---@return string
local function format_node(node)
  local status = node.type == "step" and get_step_status(node.status, node.conclusion)
    or node.type == "job" and get_job_status(node.status, node.conclusion)
    or ""

  local indent = string.rep(" ", node.indent)
  local preIcon = node.type ~= "step_log" and (node.expanded == true and "> " or "> ") or ""
  local formatted = string.format("%s%s%s %s", indent, preIcon, node.display, status)
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
    highlight = node.highlight,
    step_log = nil,
    expanded = node.expanded or false,
    node_ref = node,
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
  if not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(M.buf, namespace, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local lines = get_workflow_header()

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
    end, { silent = true, noremap = true, buffer = M.buf })
  end
  for binding, cb in pairs(keymaps) do
    vim.keymap.set("n", binding, function()
      cb(M)
    end, { silent = true, noremap = true, buffer = M.buf })
  end
end

M.refresh = function()
  print_lines()
end

local workflow_limit = 100

local function get_workflow_runs_sync(co)
  local lines = {}
  vim.fn.jobstart(
    "gh run list --json conclusion,displayTitle,event,headBranch,name,number,status,updatedAt,databaseId -L "
      .. workflow_limit,
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

  local picker = pickers.new(bufnr, {
    prompt_title = title,
    finder = finders.new_table {
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
    sorter = config.values.generic_sorter {},
    preview = true,
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selection = state.get_selected_entry()
        actions.close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "<CR>", function(prompt_bufnr)
        local selection = state.get_selected_entry()
        actions.close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "q", function(prompt_bufnr)
        actions.close(prompt_bufnr)
      end)
      return true
    end,
  })
  picker:find()
end

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
    render,
    "Workflow runs",
    function(self, entry)
      local id = entry.value.id
      M.buf = self.state.bufnr
      populate_preview_buffer(id, self.state.bufnr)
    end
  )
end

M.refetch = function()
  local id = M.current_wf.databaseId
  M.wf_cache[id] = nil
  M.current_wf = nil
  populate_preview_buffer(id, M.buf)
end

return M
