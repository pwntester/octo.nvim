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
---@field repo? string

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
---@field cancel function
---@field rerun function

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
---@field children WorkflowNode[]

local M = {
  buf = nil,
  buf_name = "",
  filetype = "",
  tree = {},
  current_wf = nil,
  ---@type table<string, WorkflowRun>
  wf_cache = {},
  log_cache = {},
  rendered_lines = {},
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

---@param logLine string?
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
function M.traverse(tree, cb)
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

---@param lines string[]
local function collapse_groups(lines)
  local collapsed = {} ---@type string[]
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

---@param value string
---@param indent number
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

local function create_log_header(display, indent)
  return {
    display = display,
    id = "log-header:" .. display,
    expanded = false,
    indent = indent + 2,
    type = "step_log",
    highlight = "NonText",
    icon = "",
    preIcon = "",
    children = {},
  }
end

local function stdout_to_lines(stdout)
  if stdout == nil then
    return {}
  end
  if type(stdout) == "string" then
    return vim.split(stdout, "\n")
  end
  if type(stdout) == "table" then
    local lines = {}
    for _, item in ipairs(stdout) do
      if type(item) == "string" then
        vim.list_extend(lines, vim.split(item, "\n"))
      else
        local ok, str = pcall(vim.fn.blob2str, item)
        if ok and type(str) == "string" then
          vim.list_extend(lines, vim.split(str, "\n"))
        end
      end
    end
    return lines
  end
  local ok, str = pcall(vim.fn.blob2str, stdout)
  if ok and type(str) == "string" then
    return vim.split(str, "\n")
  end
  return {}
end

local function ensure_string(value)
  if type(value) == "string" then
    return value
  end
  local ok, str = pcall(vim.fn.blob2str, value)
  if ok and type(str) == "string" then
    return str
  end
  return tostring(value)
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
        vim.uv.fs_unlink(zip_location)
      end)

      if not unlink_success then
        utils.error("Error deleting logs archive: " .. unlink_error)
      end
    end
end

local function normalize_log_path(path)
  return vim.trim(path):lower():gsub("[^%w]", "")
end

local function build_log_children(lines, indent, header)
  local children = {}
  if header then
    table.insert(children, create_log_header(header, indent))
  end
  for _, collapsed in ipairs(collapse_groups(lines)) do
    local groupedLines = vim.split(ensure_string(collapsed), "\n")
    local log_child = create_log_child(groupedLines[1], indent)
    if #groupedLines > 1 then
      local sub = {}
      for i, value in ipairs(groupedLines) do
        if i ~= 1 then
          table.insert(sub, create_log_child(value, log_child.indent))
        end
      end
      log_child.children = sub
    end
    table.insert(children, log_child)
  end
  return children
end

local function ensure_log_cache(id, repo)
  if M.log_cache[id] then
    return M.log_cache[id], true
  end

  utils.info "Fetching workflow logs (this may take a while) ..."
  local reponame = repo or utils.get_remote_name()
  local cmd = {
    "gh",
    "api",
    string.format("repos/%s/actions/runs/%s/logs", reponame, id, 0),
  }

  local out = vim.system(cmd):wait()

  if out.code ~= 0 then
    utils.error("Failed to fetch logs: " .. (out.stderr or "Unknown error"))
    return nil, false
  end

  local zip_location, cleanup = write_zipped_file(out.stdout)
  local cache = {
    zip_location = zip_location,
    cleanup = cleanup,
    zip_index = nil,
    job_log_index = { entries = {}, normalized = {} },
    job_log_cache = {},
    step_log_cache = {},
  }
  M.log_cache[id] = cache
  return cache, true
end

local function ensure_zip_index(cache)
  if cache.zip_index then
    return cache.zip_index
  end

  local list = vim.system({ "unzip", "-Z1", cache.zip_location }):wait()
  if list.code ~= 0 then
    return nil
  end

  local zip_index = { entries = {}, normalized = {}, normalized_files = {}, entries_list = {} }
  for _, line in ipairs(vim.split(list.stdout or "", "\n")) do
    line = vim.trim(line)
    if line ~= "" then
      zip_index.entries[line] = true
      table.insert(zip_index.entries_list, line)
      local key = normalize_log_path(line)
      local existing = zip_index.normalized[key]
      if existing == nil then
        zip_index.normalized[key] = line
      elseif type(existing) == "string" then
        zip_index.normalized[key] = { existing, line }
      else
        table.insert(existing, line)
      end

      local basename = vim.fs.basename(line)
      local file_key = normalize_log_path(basename)
      local existing_file = zip_index.normalized_files[file_key]
      if existing_file == nil then
        zip_index.normalized_files[file_key] = line
      elseif type(existing_file) == "string" then
        zip_index.normalized_files[file_key] = { existing_file, line }
      else
        table.insert(existing_file, line)
      end

      if not line:find "/" and line:match "^%d+_.*%.txt$" then
        local job_name = vim.trim(line:sub(3, -5))
        local job_key = normalize_log_path(job_name)
        local existing_job = cache.job_log_index.normalized[job_key]
        cache.job_log_index.entries[line] = true
        if existing_job == nil then
          cache.job_log_index.normalized[job_key] = line
        elseif type(existing_job) == "string" then
          cache.job_log_index.normalized[job_key] = { existing_job, line }
        else
          table.insert(existing_job, line)
        end
      end
    end
  end

  cache.zip_index = zip_index
  return zip_index
end

local function get_step_log(node)
  if not M.current_wf then
    return
  end

  if node.type ~= "step" or node.conclusion == "skipped" then
    return
  end

  if node.status == "queued" or node.status == "in_progress" then
    utils.error "Cant view logs of running workflow..."
    return
  end

  if node.children and next(node.children) then
    return
  end

  local run_id = M.current_wf.databaseId
  local cache, ok = ensure_log_cache(run_id, M.current_wf.repo)
  if not ok or not cache then
    return
  end

  local zip_index = ensure_zip_index(cache)
  if not zip_index then
    node.children = { create_log_header("Logs unavailable", node.indent) }
    return
  end

  cache.step_log_cache[node.job_id] = cache.step_log_cache[node.job_id] or {}
  if cache.step_log_cache[node.job_id][node.number] then
    node.children = cache.step_log_cache[node.job_id][node.number]
    return
  end

  local sanitized_name = node.id:gsub("/", ""):gsub(":", ""):gsub(">", "")
  local sanitized_job_id = node.job_id:gsub("/", ""):gsub(":", ""):gsub("%.+$", "*/")
  local file_name = string.format("%s_%s.txt", node.number, sanitized_name)
  local path = vim.fs.joinpath(sanitized_job_id, file_name)
  local actual_path = path
  local use_job_log = false

  if zip_index.entries[path] then
    actual_path = path
  else
    local key = normalize_log_path(path)
    local match = zip_index.normalized[key]
    if type(match) == "string" then
      actual_path = match
    elseif type(match) == "table" and #match > 0 then
      actual_path = match[1]
    else
      local basename_key = normalize_log_path(vim.fs.basename(path))
      local file_match = zip_index.normalized_files[basename_key]
      if type(file_match) == "string" then
        actual_path = file_match
      elseif type(file_match) == "table" and #file_match > 0 then
        actual_path = file_match[1]
      else
        local job_key = normalize_log_path(node.job_id)
        local job_match = cache.job_log_index.normalized[job_key]
        if type(job_match) == "string" then
          actual_path = job_match
          use_job_log = true
        elseif type(job_match) == "table" and #job_match > 0 then
          actual_path = job_match[1]
          use_job_log = true
        else
          node.children = { create_log_header("Job log unavailable", node.indent) }
          return
        end
      end
    end
  end

  if use_job_log and cache.job_log_cache[node.job_id] then
    node.children = cache.job_log_cache[node.job_id]
    cache.step_log_cache[node.job_id][node.number] = node.children
    return
  end

  local res = vim
    .system({
      "unzip",
      "-p",
      cache.zip_location,
      actual_path,
    })
    :wait()

  if res.code ~= 0 then
    node.children = { create_log_header("Failed to extract logs", node.indent) }
    return
  end

  local lines = vim.tbl_filter(function(i) ---@param i string
    return i ~= nil and i ~= ""
  end, stdout_to_lines(res.stdout))

  node.children = build_log_children(lines, node.indent)
  cache.step_log_cache[node.job_id][node.number] = node.children
  if use_job_log then
    cache.job_log_cache[node.job_id] = node.children
  end
end

---@type table<string, fun(api: Handler): nil>
local keymaps = {
  [mappings.refresh.lhs] = function(api)
    utils.info "Refreshing..."
    api.refetch()
  end,
  [mappings.rerun.lhs] = function(api)
    utils.info "Rerunning..."
    api.rerun()
  end,
  [mappings.rerun_failed.lhs] = function(api)
    utils.info "Rerunning failed jobs..."
    api.rerun { failed = true }
  end,
  [mappings.cancel.lhs] = function(api)
    utils.info "Cancelling..."
    api.cancel()
  end,
  [mappings.open_in_browser.lhs] = function(api)
    local id = api.current_wf.databaseId
    navigation.open_in_browser("workflow_run", nil, id)
  end,
  [mappings.copy_url.lhs] = function(api)
    local url = api.current_wf.url
    utils.copy_url(url)
  end,
}

---@param tree WorkflowNode
---@param target_id string
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

---@type table<string, fun(node: WorkflowNode): nil>
local tree_keymaps = {
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
        if not next(node.children) then
          get_step_log(node)
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

local function update_job_details(id, repo)
  if M.wf_cache[id] ~= nil then
    M.refresh()
    return
  end

  gh.run.view {
    id,
    repo = repo,
    json = fields,
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.print_err(stderr)
          utils.error("Failed to get workflow run for " .. id)
        elseif output then
          ---@type WorkflowRun
          local job_details = vim.json.decode(output)
          job_details.repo = repo
          M.wf_cache[id] = job_details
          M.current_wf = job_details
          M.tree = generate_workflow_tree(job_details)
          M.refresh()
        end
      end,
    },
  }
end

---@param id string
---@param repo? string
---@param buf integer
local function populate_preview_buffer(id, repo, buf)
  local cached = M.wf_cache[id]
  if cached and vim.api.nvim_buf_is_valid(buf) then
    M.current_wf = cached
    M.tree = generate_workflow_tree(cached)
    M.refresh()
  else
    update_job_details(id, repo)
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
  vim.bo[M.buf].modifiable = true
  local lines = get_workflow_header()

  local stringified_tree = tree_to_string(M.tree, {})
  for _, value in ipairs(stringified_tree) do
    table.insert(lines, value)
  end

  M.rendered_lines = lines

  local highlights = {} ---@type { index: integer, highlight: string }[]

  local string_lines = {}

  for index, line_def in ipairs(lines) do
    table.insert(string_lines, line_def.value)
    table.insert(highlights, { index = index - 1, highlight = line_def.highlight })
  end

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, string_lines)
  vim.bo[M.buf].modifiable = false

  for _, vl in ipairs(highlights) do
    if vl.highlight then
      vim.api.nvim_buf_set_extmark(M.buf, namespace, vl.index, 0, {
        end_line = vl.index + 1,
        hl_group = vl.highlight,
      })
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

  vim.keymap.set("n", "]s", function()
    M.jump_to_step(1)
  end, { silent = true, noremap = true, buffer = M.buf })
  vim.keymap.set("n", "[s", function()
    M.jump_to_step(-1)
  end, { silent = true, noremap = true, buffer = M.buf })
  vim.keymap.set("n", "]j", function()
    M.jump_to_job(1)
  end, { silent = true, noremap = true, buffer = M.buf })
  vim.keymap.set("n", "[j", function()
    M.jump_to_job(-1)
  end, { silent = true, noremap = true, buffer = M.buf })
end

function M.refresh()
  print_lines()
end

local function jump_to_line(direction, predicate, edge_message)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local current = M.rendered_lines[current_line]
  local on_match = current and predicate(current) or false
  local index = current_line + direction
  while index >= 1 and index <= #M.rendered_lines do
    local line = M.rendered_lines[index]
    if line and predicate(line) then
      vim.api.nvim_win_set_cursor(0, { index, 0 })
      return
    end
    index = index + direction
  end
  if edge_message and on_match then
    utils.info(edge_message)
  end
end

function M.jump_to_step(direction)
  jump_to_line(direction, function(line)
    return line.type == "step"
  end, direction > 0 and "Last step" or "First step")
end

function M.jump_to_job(direction)
  jump_to_line(direction, function(line)
    return line.type == "job"
  end, direction > 0 and "Last job" or "First job")
end

local workflow_limit = 100

local run_list_fields = "conclusion,displayTitle,event,headBranch,name,number,status,updatedAt,databaseId"

local function get_workflow_runs_sync(opts)
  opts = opts or {}

  local lines = {}
  local repo = opts.repo or utils.get_remote_name()
  local output, stderr = gh.run.list {
    json = run_list_fields,
    limit = workflow_limit,
    branch = opts.branch,
    repo = repo,
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    utils.print_err(stderr)
    utils.error "Failed to get workflow runs"
  elseif output then
    ---@type {
    ---  conclusion: string,
    ---  displayTitle: string,
    ---  event: string,
    ---  headBranch: string,
    ---  name: string,
    ---  number: integer,
    ---  status: string,
    ---  updatedAt: string,
    ---  databaseId: integer,
    ---}[]
    local json = vim.json.decode(output)
    for _, value in ipairs(json) do
      local status = value.status == "queued" and icons.pending
        or value.status == "in_progress" and icons.in_progress
        or value.conclusion == "failure" and icons.failed
        or icons.succeeded

      local conclusion = value.conclusion == "skipped" and icons.skipped
        or value.conclusion == "failure" and icons.failed
        or ""

      local display ---@type string
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
        repo = repo,
      }
      table.insert(lines, wf_run)
    end
  end

  return lines
end

---@param selected { id: string, repo: string }
function M.render(selected)
  local new_buf = vim.api.nvim_create_buf(true, true)
  M.buf = new_buf
  vim.api.nvim_set_current_buf(new_buf)
  populate_preview_buffer(selected.id, selected.repo, new_buf)
  vim.api.nvim_buf_set_name(new_buf, string.format("octo-workflow-run:%s:%d", selected.id, new_buf))
end

function M.previewer(self, entry)
  ---@type string
  local id = entry.value.id
  local repo = entry.value.repo
  M.buf = self.state.bufnr
  populate_preview_buffer(id, repo, self.state.bufnr)
end

function M.list(opts)
  utils.info "Fetching workflow runs (this may take a while) ..."
  local wf_runs = get_workflow_runs_sync(opts)

  require("octo.picker").workflow_runs(wf_runs, "Workflow runs", M.render)
end

function M.refetch()
  local id = M.current_wf.databaseId
  M.wf_cache[id] = nil
  M.current_wf = nil
  M.log_cache[id] = nil
  populate_preview_buffer(id, nil, M.buf)
end

---@param db_id number | nil
function M.cancel(db_id)
  local id = db_id or M.current_wf.databaseId
  local _, stderr = gh.run.cancel {
    id,
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    utils.print_err(stderr)
    utils.error "Failed to cancel workflow run"
  else
    utils.info "Cancelled"
  end
  M.refetch()
end

---@param opts { db_id: number | nil, failed: boolean | nil }
function M.rerun(opts)
  opts = opts or {}
  local failed_jobs = opts.failed == true
  local id = opts.db_id or (M.current_wf and M.current_wf.databaseId)
  local _, stderr = gh.run.rerun {
    id,
    failed = failed_jobs,
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    utils.print_err(stderr)
    utils.error "Failed to rerun workflow run"
  else
    utils.info "Rerun queued"
  end
  M.refetch()
end

local function find_workflow_path_by_name(workflow_name)
  local jq = ([[
    map(select(.name == "{name}")) | .[0].path
  ]]):gsub("{name}", workflow_name)

  return gh.workflow.list {
    json = "name,path",
    jq = jq,
    opts = { mode = "sync" },
  }
end

function M.edit(workflow_name)
  if workflow_name == "Dependabot Updates" then
    vim.cmd.edit ".github/dependabot.yml"
    return
  end

  local path = find_workflow_path_by_name(workflow_name)

  if string.match(path, "^dynamic") then
    utils.error "Dynamic workflows are not supported"
    return
  end

  vim.cmd.edit(path)
end

function M.workflow_list(opts)
  opts = opts or {}

  if not opts.cb then
    error "Callback is required"
  end

  local names = gh.workflow.list {
    json = "name",
    jq = "map(.name)",
    opts = { mode = "sync" },
  }
  if not names then
    utils.error "Failed to get workflow names"
    return
  end

  vim.ui.select(vim.json.decode(names), {
    prompt = "Select a workflow: ",
  }, function(selected)
    if not selected then
      return
    end
    opts.cb(selected)
  end)
end

return M
