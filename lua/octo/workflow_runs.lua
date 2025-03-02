local namespace = require("octo.constants").OCTO_WORKFLOW_NS
local mappings = require("octo.config").values.mappings.runs
local icons = require("octo.config").values.runs.icons
local navigation = require "octo.navigation"
local utils = require "octo.utils"
local gh = require "octo.gh"

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
local function generate_workflow_tree(data)
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

  for _, job in ipairs(data.jobs or {}) do
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

    for _, step in ipairs(job.steps or {}) do
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

local function extract_after_timestamp(logLine)
  if logLine == nil then
    return ""
  end
  local result = logLine:match "%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s*(.*)"
  return result or ""
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
    if extract_after_timestamp(line):find "##%[group%]" then
      current_group = { line }
    elseif extract_after_timestamp(line):find "##%[endgroup%]" then
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
    display = extract_after_timestamp(value)
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

local function get_temp_filepath(length)
  length = length or 7
  local name = ""
  while length > #name do
    name = name .. string.char(math.random(65, 65 + 25)):lower()
  end
  return vim.fs.joinpath(vim.fs.normalize(vim.fn.stdpath "cache"), name)
end

---@param stdout string - The zip content to write
local function write_zipped_file(stdout)
  local zip_location = get_temp_filepath()
  local file = io.open(zip_location, "wb")
  if not file then
    utils.error "Failed to create temporary file"
    return
  end

  file:write(stdout)
  file:close()

  return zip_location,
    function()
      local unlink_success, unlink_error = pcall(function()
        vim.loop.fs_unlink(zip_location)
      end)

      if not unlink_success then
        utils.error("Error deleting logs archive: " .. unlink_error)
      end
    end
end

local function get_logs(id)
  utils.info "Fetching workflow logs (this may take a while) ..."
  local reponame = utils.get_remote_name()
  local cmd = {
    "gh",
    "api",
    string.format("repos/%s/actions/runs/%s/logs", reponame, id, 0),
  }
  local out = vim.system(cmd):wait()

  if out.code ~= 0 then
    utils.error("Failed to fetch logs: " .. (out.stderr or "Unknown error"))
    return
  end

  local zip_location, cleanup = write_zipped_file(out.stdout)

  ---@param node WorkflowNode
  M.traverse(M.tree, function(node)
    if node.type ~= "step" or node.conclusion == "skipped" then
      return
    end

    local sanitized_name = node.id:gsub("/", ""):gsub(":", ""):gsub(">", "")
    --Make more than 3 consecutive dots at the end of line into */. This avoids a bug with unreliable filename endings
    local sanitized_job_id = node.job_id:gsub("/", ""):gsub(":", ""):gsub("%.+$", "*/")
    local file_name = string.format("%s_%s.txt", node.number, sanitized_name)
    local path = vim.fs.joinpath(sanitized_job_id, file_name)
    print(path)
    local res = vim
      .system({
        "unzip",
        "-p",
        zip_location,
        path,
      })
      :wait()

    if res.code ~= 0 then
      utils.error("Failed to extract logs for " .. node.id)
    end

    local lines = vim.tbl_filter(function(i)
      return i ~= nil and i ~= ""
    end, vim.split(res.stdout, "\n"))

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
  if cleanup then
    cleanup()
  end
end

local keymaps = {
  ---@param api Handler
  [mappings.refresh.lhs] = function(api)
    utils.info "refreshing..."
    api.refetch()
  end,
  [mappings.open_in_browser.lhs] = function(api)
    local id = api.current_wf.databaseId
    navigation.open_in_browser("workflow_run", nil, id)
  end,
  [mappings.copy_url.lhs] = function(api)
    local url = api.current_wf.url
    vim.fn.setreg("+", url, "c")
    utils.info("Copied URL '" .. url .. "' to the system clipboard (+ register)")
  end,
}

local function find_parent(tree, target_id)
  if not tree or not tree.children then
    return nil
  end

  for _, child in pairs(tree.children) do
    if child.id == target_id then
      return tree
    end
    local parent = find_parent(child, target_id)
    if parent then
      return parent
    end
  end

  return nil
end

local tree_keymaps = {
  ---@param node WorkflowNode
  [mappings.expand_step.lhs] = function(node)
    if node.type == "step_log" and not next(node.children) then
      local parent = find_parent(M.tree, node.id)
      if parent then
        parent.expanded = false
        M.refresh()
        return
      end
    end

    if node.expanded == false then
      node.expanded = true
      if node.type == "step" then
        if node.conclusion == "in_progress" then
          utils.error "Cant view logs of running workflow..."
          return
        end
        if not next(node.children) then
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

  gh.run.view {
    id,
    json = fields,
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
          utils.error("Failed to get workflow run for " .. id)
        elseif output then
          job_details = vim.fn.json_decode(output)
          M.wf_cache[id] = job_details
          M.current_wf = job_details
          M.tree = generate_workflow_tree(job_details)
          M.refresh()
        end
      end,
    },
  }
end

local function populate_preview_buffer(id, buf)
  local cached = M.wf_cache[id]
  if cached and vim.api.nvim_buf_is_valid(buf) then
    M.current_wf = cached
    M.tree = generate_workflow_tree(cached)
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
  local preIcon = node.type ~= "step_log" and (node.expanded == true and "∨ " or "> ") or ""
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

local run_list_fields = "conclusion,displayTitle,event,headBranch,name,number,status,updatedAt,databaseId"

local function get_workflow_runs_sync(opts)
  opts = opts or {}

  local lines = {}
  local output, stderr = gh.run.list {
    json = run_list_fields,
    limit = workflow_limit,
    branch = opts.branch,
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    vim.api.nvim_err_writeln(stderr)
    utils.error "Failed to get workflow runs"
  elseif output then
    local json = vim.fn.json_decode(output)
    for _, value in ipairs(json) do
      local status = value.status == "queued" and icons.pending
        or value.status == "in_progress" and icons.in_progress
        or value.conclusion == "failure" and icons.failed
        or icons.succeeded

      local conclusion = value.conclusion == "skipped" and icons.skipped
        or value.conclusion == "failure" and icons.failed
        or ""

      local display
      if opts.branch == nil then
        display = string.format("%s (%s)", value.name, value.headBranch)
      else
        display = value.name
      end

      local wf_run = {
        status = status,
        title = value.displayTitle,
        display = display .. " " .. conclusion,
        value = value.databaseId,
        branch = value.headBranch,
        name = value.name,
        age = utils.format_date(value.updatedAt),
        id = value.databaseId,
      }
      table.insert(lines, wf_run)
    end
  end

  return lines
end

local function render(selected)
  local new_buf = vim.api.nvim_create_buf(true, true)
  M.buf = new_buf
  vim.api.nvim_set_current_buf(new_buf)
  populate_preview_buffer(selected.id, new_buf)
  vim.api.nvim_buf_set_name(new_buf, "" .. selected.id)
end

M.previewer = function(self, entry)
  local id = entry.value.id
  M.buf = self.state.bufnr
  populate_preview_buffer(id, self.state.bufnr)
end

M.list = function(opts)
  utils.info "Fetching workflow runs (this may take a while) ..."
  local wf_runs = get_workflow_runs_sync(opts)

  require("octo.picker").workflow_runs(wf_runs, "Workflow runs", render)
end

M.refetch = function()
  local id = M.current_wf.databaseId
  M.wf_cache[id] = nil
  M.current_wf = nil
  populate_preview_buffer(id, M.buf)
end

return M
