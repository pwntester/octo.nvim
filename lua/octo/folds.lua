local config = require "octo.config"

local M = {}

function M.setup() end

---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@param is_opened boolean
function M.create(bufnr, start_line, end_line, is_opened)
  if config.values.ui.use_foldtext then
    start_line = start_line - 1
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd [[setlocal foldmethod=manual]]
    vim.cmd(string.format("%d,%dfold", start_line, end_line))
    if is_opened then
      vim.cmd(string.format("%d,%dfoldopen", start_line, end_line))
    end
  end)
end

--- Scan buffer lines for <details>...</details> HTML blocks and create
--- closed folds for each one. The <summary> text (if present) is shown
--- as the fold line via virtual text.
---@param bufnr integer
---@param start_line integer first buffer line to scan (1-based)
---@param end_line integer last buffer line to scan (1-based)
function M.create_details_folds(bufnr, start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local details_ns = vim.api.nvim_create_namespace "octo_details_folds"

  -- Collect nested <details> blocks using a stack
  local stack = {} ---@type {open_line: integer, summary: string?, in_summary: boolean}[]
  local blocks = {} ---@type {open_line: integer, close_line: integer, summary: string?}[]

  for i, line in ipairs(lines) do
    local buf_line = start_line + i - 1 -- 1-based buffer line number

    -- Detect <details> (possibly with attributes)
    if line:match "%s*<details[^>]*>" then
      table.insert(stack, { open_line = buf_line, summary = nil, in_summary = false })
    end

    if #stack > 0 then
      local top = stack[#stack]

      -- Capture <summary>...</summary> on the same line
      if not top.summary then
        local inline_summary = line:match "<summary>(.-)</summary>"
        if inline_summary then
          top.summary = vim.trim(inline_summary)
        elseif line:match "<summary>" then
          -- Multi-line summary: start collecting
          top.in_summary = true
          top.summary = ""
          local after = line:match "<summary>(.*)"
          if after and vim.trim(after) ~= "" then
            top.summary = vim.trim(after)
          end
        elseif top.in_summary then
          if line:match "</summary>" then
            -- End of multi-line summary
            local before = line:match "(.*)</summary>"
            if before and vim.trim(before) ~= "" then
              top.summary = ((top.summary ~= "" and top.summary .. " " or "") .. vim.trim(before))
            end
            top.in_summary = false
          else
            -- Middle of multi-line summary
            local trimmed = vim.trim(line)
            if trimmed ~= "" then
              top.summary = ((top.summary ~= "" and top.summary .. " " or "") .. trimmed)
            end
          end
        end
      end

      -- Detect </details>
      if line:match "%s*</details>" then
        local block = table.remove(stack)
        block.close_line = buf_line
        block.in_summary = nil
        table.insert(blocks, block)
      end
    end
  end

  -- Create folds for each block (closed by default).
  -- We create folds directly here instead of using M.create(), because
  -- M.create() shifts start_line back by 1 for use_foldtext. That offset
  -- is meant for comment header folds, not details folds — it would cause
  -- a mismatch between the fold start and the extmark line.
  for _, block in ipairs(blocks) do
    local fold_start = block.open_line
    local fold_end = block.close_line

    -- Place virtual text with summary on the fold start line
    local summary_text = block.summary and block.summary ~= "" and block.summary or "Details"
    vim.api.nvim_buf_set_extmark(bufnr, details_ns, fold_start - 1, 0, {
      virt_text = { { "▶ " .. summary_text .. " …", "Comment" } },
      virt_text_pos = "overlay",
    })

    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd [[setlocal foldmethod=manual]]
      vim.cmd(string.format("%d,%dfold", fold_start, fold_end))
    end)
  end
end

--- Folds will already have correct highlighting, but the fold background will
--- extend over the entire line. This function will make sure the whitespace
--- before the fold icon is using no background.
--- For <details> folds, it shows the summary text instead.
function M.foldtext()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.v.foldstart
  local details_ns = vim.api.nvim_create_namespace "octo_details_folds"

  -- Check for <details> fold extmarks first
  local details_extmark =
    vim.api.nvim_buf_get_extmarks(buf, details_ns, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })[1]
  if details_extmark then
    local virt_text = vim.tbl_get(details_extmark, 4, "virt_text")
    if virt_text then
      local line_count = vim.v.foldend - vim.v.foldstart + 1
      local result = {}
      vim.list_extend(result, virt_text)
      table.insert(result, { " (" .. line_count .. " lines)", "Comment" })
      return result
    end
  end

  -- Default behavior for other folds (comment headers, etc.)
  local extmark =
    vim.api.nvim_buf_get_extmarks(buf, -1, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true, type = "virt_text" })[1]

  local text = vim.tbl_get(extmark, 4, "virt_text", 1, 1)
  if text then
    return { { text:match "^%s+", "Normal" } }
  end
end

return M
