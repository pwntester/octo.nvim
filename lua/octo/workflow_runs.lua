local M = {}

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
local function get_job_details_lines(details)
  local lines = {}
  table.insert(
    lines,
    string.format("%s %s", details.displayTitle, get_workflow_status(details.status, details.conclusion))
  )

  table.insert(lines, "")

  table.insert(lines, string.format("Branch: %s", details.headBranch))
  table.insert(lines, string.format("Event: %s", details.event))
  if #details.conclusion > 0 then
    table.insert(lines, string.format("Finished: %s", utils.format_date(details.updatedAt)))
  elseif #details.startedAt > 0 then
    table.insert(lines, string.format("Started: %s", utils.format_date(details.startedAt)))
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
      table.insert(
        lines,
        string.format("%s%d. %s %s", stepIndent, i, step.name, get_step_status(step.status, step.conclusion))
      )
      if i ~= #job.steps then
        table.insert(lines, "")
      end
    end
    table.insert(lines, "")
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
    end,
    on_exit = function(_, b)
      if b == 0 then
        local lines = get_job_details_lines(job_details)
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Question", 0, 0, -1)
          vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 2, 0, -1)
          vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 3, 0, -1)
          vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 4, 0, -1)
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
  if wf_cache[id] ~= nil and vim.api.nvim_buf_is_valid(buf) then
    local lines = get_job_details_lines(wf_cache[id])
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Question", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 2, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 3, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, require("octo.constants").OCTO_WORKFLOW_NS, "Directory", 4, 0, -1)
  end
  update_job_details(id, buf)
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

M.list = function()
  vim.notify "Fetching workflow runs (this may take a while) ..."
  local co = coroutine.running()
  local wf_runs = get_workflow_runs_sync(co)

  preview_picker(
    nil,
    wf_runs,
    function(i)
      local new_buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_set_current_buf(new_buf)
      populate_preview_buffer(i.id, new_buf)
      --TODO: add fold logic
    end,
    "Workflow runs",
    function(self, entry)
      local id = entry.value.id
      populate_preview_buffer(id, self.state.bufnr)
    end
  )
end

return M
