---@diagnostic disable
local config = require "octo.config"

-- Ensure config is initialized for folds.lua
config.values = config.values or {}
config.values.ui = config.values.ui or {}
if config.values.ui.use_foldtext == nil then
  config.values.ui.use_foldtext = true
end

local folds = require "octo.folds"
local eq = assert.are.same

--- Helper: create a scratch buffer + window, write lines, run create_details_folds,
--- and return the buffer handle and window handle for inspection.
local function setup_buf(input_lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, input_lines)
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = 120,
    height = 60,
    row = 0,
    col = 0,
  })
  folds.create_details_folds(bufnr, 1, #input_lines)
  return bufnr, win
end

--- Helper: get all extmarks in the details namespace for a buffer.
local function get_details_extmarks(bufnr)
  local ns = vim.api.nvim_create_namespace "octo_details_folds"
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

--- Helper: get only extmarks that have virt_text overlays (filters out line_hl_group-only marks).
local function get_overlay_extmarks(bufnr)
  local all = get_details_extmarks(bufnr)
  local result = {}
  for _, ext in ipairs(all) do
    if ext[4].virt_text then
      table.insert(result, ext)
    end
  end
  return result
end

--- Helper: tear down buffer and window.
local function teardown(bufnr, win)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

describe("details folds", function()
  describe("parse_details_blocks", function()
    it("parses inline <details><summary>...</summary> on same line", function()
      local lines = {
        "<details><summary>This is the summary</summary>",
        "Here is the content",
        "</details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq(1, blocks[1].open_line)
      eq(3, blocks[1].close_line)
      eq("This is the summary", blocks[1].summary)
      -- open_line and close_line are both tag lines
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 1))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 3))
    end)

    it("parses <details> with blank lines before <summary>", function()
      local lines = {
        "",
        "",
        "<details>",
        "",
        "<summary>Example Usage</summary>",
        "",
        "",
        "```python",
        "for i, value in enumerate([1, 2, 3]):",
        "    print(i, value)",
        "```",
        "",
        "</details>",
        "",
        "",
        "More text below",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq(3, blocks[1].open_line)
      eq(13, blocks[1].close_line)
      eq("Example Usage", blocks[1].summary)
      -- <details> line, <summary> line, and </details> line are tag lines
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 3))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 5))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 13))
    end)

    it("parses multi-line <summary> tag", function()
      local lines = {
        "<details>",
        "<summary>",
        "Multi line title",
        "</summary>",
        "content here",
        "</details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq("Multi line title", blocks[1].summary)
      -- <summary>, text line, </summary> are all tag lines
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 2))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 3))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 4))
    end)

    it("parses nested <details> blocks", function()
      local lines = {
        "Some text",
        "",
        "<details><summary>Outer block summary</summary>",
        "",
        "Let's hear what the inner block has to say:",
        "",
        "<details>",
        "<summary>",
        "Inner block summary",
        "</summary>",
        "",
        "A long story...",
        "",
        "About the...",
        "",
        "Inner block's details...",
        "</details>",
        "",
        "That was a good story!",
        "",
        "</details>",
        "",
        "Some other text!",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(2, #blocks)

      -- Inner block pops first from the stack
      eq(7, blocks[1].open_line)
      eq(17, blocks[1].close_line)
      eq("Inner block summary", blocks[1].summary)
      -- Inner tag lines: <details>(7), <summary>(8), text(9), </summary>(10), </details>(17)
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 7))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 8))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 9))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 10))
      assert.is_true(vim.tbl_contains(blocks[1].tag_lines, 17))

      -- Outer block
      eq(3, blocks[2].open_line)
      eq(21, blocks[2].close_line)
      eq("Outer block summary", blocks[2].summary)
      assert.is_true(vim.tbl_contains(blocks[2].tag_lines, 3))
      assert.is_true(vim.tbl_contains(blocks[2].tag_lines, 21))
    end)

    it("defaults summary to 'Details' when no <summary> tag", function()
      local lines = {
        "<details>",
        "Some hidden content",
        "</details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq("Details", blocks[1].summary)
    end)

    it("handles start_line offset correctly", function()
      local lines = {
        "<details>",
        "<summary>Offset test</summary>",
        "content",
        "</details>",
      }
      -- Simulate these lines starting at buffer line 10
      local blocks = folds.parse_details_blocks(lines, 10)
      eq(1, #blocks)
      eq(10, blocks[1].open_line)
      eq(13, blocks[1].close_line)
      eq("Offset test", blocks[1].summary)
    end)

    it("handles <details> with attributes", function()
      local lines = {
        '<details open="true">',
        "<summary>Open by default</summary>",
        "content",
        "</details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq("Open by default", blocks[1].summary)
      eq(true, blocks[1].is_open)
    end)

    it("sets is_open=false when open attribute is absent", function()
      local lines = {
        "<details>",
        "<summary>Closed</summary>",
        "content",
        "</details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq(false, blocks[1].is_open)
    end)

    it("handles <details open> without a value", function()
      local lines = {
        "<details open>",
        "<summary>Boolean open</summary>",
        "content",
        "</details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq(true, blocks[1].is_open)
    end)

    it("parses uppercase <DETAILS> and <SUMMARY> tags", function()
      local lines = {
        "<DETAILS>",
        "<SUMMARY>Uppercase tags</SUMMARY>",
        "content",
        "</DETAILS>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq("Uppercase tags", blocks[1].summary)
      eq(1, blocks[1].open_line)
      eq(4, blocks[1].close_line)
    end)

    it("parses mixed-case tags", function()
      local lines = {
        "<Details>",
        "<Summary>Mixed case</Summary>",
        "content",
        "</Details>",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(1, #blocks)
      eq("Mixed case", blocks[1].summary)
    end)

    it("ignores </details> with trailing content on the same line", function()
      local lines = {
        "<details>",
        "<summary>Test</summary>",
        "content",
        "</details> and more text",
      }
      local blocks = folds.parse_details_blocks(lines, 1)
      eq(0, #blocks)
    end)
  end)

  describe("create_details_folds", function()
    it("creates folds and hides tag lines for inline details+summary", function()
      local lines = {
        "<details><summary>This is the summary</summary>",
        "Here is the content",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_overlay_extmarks(bufnr)

      -- Should have 2 overlay extmarks: summary overlay on line 1, blank on </details> line 3
      eq(2, #extmarks)

      -- First extmark (line 1): summary overlay
      local vt1 = vim.tbl_get(extmarks[1], 4, "virt_text", 1, 1)
      assert.is_true(vt1:find("This is the summary", 1, true) ~= nil)

      -- Second extmark (line 3): blank overlay hiding </details>
      local vt2 = vim.tbl_get(extmarks[2], 4, "virt_text", 1, 1)
      eq(string.rep(" ", #"</details>"), vt2)

      -- Verify fold exists
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      assert.is_true(vim.fn.foldclosed(1) ~= -1)

      teardown(bufnr, win)
    end)

    it("hides <summary> and </details> lines when fold is open", function()
      local lines = {
        "",
        "",
        "<details>",
        "",
        "<summary>Example Usage</summary>",
        "",
        "",
        "```python",
        "for i, value in enumerate([1, 2, 3]):",
        "    print(i, value)",
        "```",
        "",
        "</details>",
        "",
        "",
        "More text below",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_overlay_extmarks(bufnr)

      -- Should have overlay extmarks on: <details>(3), <summary>(5), </details>(13)
      eq(3, #extmarks)

      -- Line 3 (<details>): summary overlay
      eq(2, extmarks[1][2]) -- 0-based row
      local vt1 = vim.tbl_get(extmarks[1], 4, "virt_text", 1, 1)
      assert.is_true(vt1:find("Example Usage", 1, true) ~= nil)

      -- Line 5 (<summary>Example Usage</summary>): blank overlay
      eq(4, extmarks[2][2])
      local vt2 = vim.tbl_get(extmarks[2], 4, "virt_text", 1, 1)
      eq(string.rep(" ", vim.api.nvim_strwidth "<summary>Example Usage</summary>"), vt2)

      -- Line 13 (</details>): blank overlay
      eq(12, extmarks[3][2])
      local vt3 = vim.tbl_get(extmarks[3], 4, "virt_text", 1, 1)
      eq(string.rep(" ", vim.api.nvim_strwidth "</details>"), vt3)

      teardown(bufnr, win)
    end)

    it("hides multi-line summary tag lines", function()
      local lines = {
        "<details>",
        "<summary>",
        "Inner block summary",
        "</summary>",
        "",
        "A long story...",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_overlay_extmarks(bufnr)

      -- Overlay extmarks on: <details>(1), <summary>(2), text(3), </summary>(4), </details>(7)
      eq(5, #extmarks)

      -- Line 1: summary overlay
      local vt1 = vim.tbl_get(extmarks[1], 4, "virt_text", 1, 1)
      assert.is_true(vt1:find("Inner block summary", 1, true) ~= nil)

      -- Lines 2,3,4,7: blank overlays
      for _, idx in ipairs { 2, 3, 4, 5 } do
        local vt = vim.tbl_get(extmarks[idx], 4, "virt_text", 1, 1)
        assert.is_true(vim.trim(vt) == "", "extmark " .. idx .. " should be blank, got: " .. vt)
      end

      teardown(bufnr, win)
    end)

    it("handles nested blocks: hides all tag lines for both", function()
      local lines = {
        "Some text",
        "",
        "<details><summary>Outer block summary</summary>",
        "",
        "Let's hear what the inner block has to say:",
        "",
        "<details>",
        "<summary>",
        "Inner block summary",
        "</summary>",
        "",
        "A long story...",
        "",
        "About the...",
        "",
        "Inner block's details...",
        "</details>",
        "",
        "That was a good story!",
        "",
        "</details>",
        "",
        "Some other text!",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_overlay_extmarks(bufnr)

      -- Outer tag lines: 3 (details+summary), 21 (</details>)
      -- Inner tag lines: 7 (<details>), 8 (<summary>), 9 (text), 10 (</summary>), 17 (</details>)
      -- Total overlay extmarks: 2 + 5 = 7
      eq(7, #extmarks)

      -- Outer <details> line 3: summary overlay
      eq(2, extmarks[1][2])
      local outer_vt = vim.tbl_get(extmarks[1], 4, "virt_text", 1, 1)
      assert.is_true(outer_vt:find("Outer block summary", 1, true) ~= nil)
      -- Total overlay width (across chunks) should cover the long underlying line
      local outer_chunks = vim.tbl_get(extmarks[1], 4, "virt_text")
      local outer_total = 0
      for _, chunk in ipairs(outer_chunks) do
        outer_total = outer_total + vim.api.nvim_strwidth(chunk[1])
      end
      assert.is_true(outer_total >= vim.api.nvim_strwidth "<details><summary>Outer block summary</summary>")

      -- Inner <details> line 7: summary overlay
      eq(6, extmarks[2][2])
      local inner_vt = vim.tbl_get(extmarks[2], 4, "virt_text", 1, 1)
      assert.is_true(inner_vt:find("Inner block summary", 1, true) ~= nil)

      teardown(bufnr, win)
    end)

    it("summary overlay is padded to cover underlying line text", function()
      local long_line = "<details><summary>Short</summary>"
      local lines = {
        long_line,
        "content",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_overlay_extmarks(bufnr)

      -- Total width across all virt_text chunks should cover the underlying line
      local vt_chunks = vim.tbl_get(extmarks[1], 4, "virt_text")
      local total_width = 0
      for _, chunk in ipairs(vt_chunks) do
        total_width = total_width + vim.api.nvim_strwidth(chunk[1])
      end
      assert.is_true(total_width >= vim.api.nvim_strwidth(long_line))

      teardown(bufnr, win)
    end)

    it("applies OctoDetailsBlock line highlight to all lines in the block", function()
      local lines = {
        "<details><summary>BG test</summary>",
        "content line 1",
        "content line 2",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_details_extmarks(bufnr)

      -- Every line from fold_start(1) to fold_end(4) should have line_hl_group
      for row = 0, 3 do
        local found = false
        for _, ext in ipairs(extmarks) do
          if ext[2] == row and ext[4].line_hl_group == "OctoDetailsBlock" then
            found = true
            break
          end
        end
        assert.is_true(found, "line " .. (row + 1) .. " should have OctoDetailsBlock line_hl_group")
      end

      -- Lines outside the block should NOT have the highlight
      -- (there are no lines outside in this case, but verify extmark count is bounded)
      for _, ext in ipairs(extmarks) do
        local row = ext[2]
        assert.is_true(row >= 0 and row <= 3, "no extmarks should exist outside fold range")
      end

      teardown(bufnr, win)
    end)

    it("summary overlay starts with closed arrow when fold is created", function()
      local lines = {
        "<details><summary>Arrow test</summary>",
        "content",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_details_extmarks(bufnr)

      local vt = vim.tbl_get(extmarks[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(vt, "▶"), "summary should start with ▶ when fold is closed")

      teardown(bufnr, win)
    end)

    it("arrow changes to ▼ when fold is opened and back to ▶ when closed", function()
      local lines = {
        "<details><summary>Toggle test</summary>",
        "content",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local ns = vim.api.nvim_create_namespace "octo_details_folds"

      -- Initially closed → ▶
      local exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      local vt = vim.tbl_get(exts[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(vt, "▶"), "should start with ▶")

      -- Open the fold
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.cmd "normal! zo"
      folds.update_details_arrows(bufnr)

      exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      vt = vim.tbl_get(exts[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(vt, "▼"), "should be ▼ after opening fold")

      -- Close it again
      vim.cmd "normal! zc"
      folds.update_details_arrows(bufnr)

      exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      vt = vim.tbl_get(exts[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(vt, "▶"), "should be ▶ after closing fold again")

      teardown(bufnr, win)
    end)

    it("arrow updates correctly for nested blocks", function()
      local lines = {
        "<details><summary>Outer</summary>",
        "<details><summary>Inner</summary>",
        "content",
        "</details>",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)
      local ns = vim.api.nvim_create_namespace "octo_details_folds"

      -- Open all folds
      vim.cmd "normal! zR"
      folds.update_details_arrows(bufnr)

      -- Both should be ▼
      local outer_exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      local inner_exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 1, 0 }, { 1, -1 }, { details = true })
      local outer_vt = vim.tbl_get(outer_exts[1], 4, "virt_text", 1, 1)
      local inner_vt = vim.tbl_get(inner_exts[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(outer_vt, "▼"), "outer should be ▼ when open")
      assert.is_true(vim.startswith(inner_vt, "▼"), "inner should be ▼ when open")

      -- Close all folds
      vim.cmd "normal! zM"
      folds.update_details_arrows(bufnr)

      outer_exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      outer_vt = vim.tbl_get(outer_exts[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(outer_vt, "▶"), "outer should be ▶ when closed")

      teardown(bufnr, win)
    end)

    it("creates open fold for <details open>", function()
      local lines = {
        "<details open>",
        "<summary>Open block</summary>",
        "visible content",
        "</details>",
      }
      local bufnr, win = setup_buf(lines)

      -- Fold should exist but be open
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      assert.is_true(vim.fn.foldclosed(1) == -1, "fold should be open for <details open>")

      -- Arrow should be ▼ (open)
      local ns = vim.api.nvim_create_namespace "octo_details_folds"
      local exts = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      local vt = vim.tbl_get(exts[1], 4, "virt_text", 1, 1)
      assert.is_true(vim.startswith(vt, "▼"), "arrow should be ▼ for open fold")

      teardown(bufnr, win)
    end)

    it("does not create extmarks when there are no <details> blocks", function()
      local lines = {
        "Just some regular text",
        "No HTML here",
      }
      local bufnr, win = setup_buf(lines)
      local extmarks = get_overlay_extmarks(bufnr)
      eq(0, #extmarks)
      teardown(bufnr, win)
    end)
  end)
end)
