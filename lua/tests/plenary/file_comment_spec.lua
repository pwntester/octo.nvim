---@diagnostic disable
local eq = assert.are.same

describe("file-level review comments:", function()
  local ReviewThread = require("octo.reviews.thread").ReviewThread
  local reviews = require "octo.reviews"
  local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
  local gh = require "octo.gh"
  local mutations = require "octo.gh.mutations"

  describe("ReviewThread:stub", function()
    local opts = {
      line1 = 1,
      line2 = 1,
      file_path = "lua/foo.lua",
      split = "RIGHT",
      diff_hunk = "",
      commit = "abc123",
      commit_abbrev = "abc",
      review_id = "R_1",
    }

    it("defaults to a line-level thread", function()
      eq("LINE", ReviewThread:stub(opts).subjectType)
    end)

    it("creates a file-level thread", function()
      local thread = ReviewThread:stub(vim.tbl_extend("force", opts, { subject_type = "FILE" }))
      eq("FILE", thread.subjectType)
      eq(-1, thread.id)
      eq("lua/foo.lua", thread.path)
    end)
  end)

  describe("Review:update_threads", function()
    it("pins file-level threads to the first line", function()
      local review = setmetatable({ threads = {} }, { __index = reviews.Review })
      review:update_threads {
        {
          id = "T_1",
          path = "lua/foo.lua",
          diffSide = "RIGHT",
          subjectType = "FILE",
          line = vim.NIL,
          originalLine = vim.NIL,
          startLine = vim.NIL,
          originalStartLine = vim.NIL,
          isOutdated = false,
          comments = { nodes = {} },
        },
      }
      local thread = review.threads["T_1"]
      eq(1, thread.line)
      eq(1, thread.startLine)
      eq(1, thread.originalLine)
      eq(1, thread.originalStartLine)
      eq("RIGHT", thread.startDiffSide)
    end)
  end)

  local function file_thread(id, path, created_at)
    return {
      id = id,
      path = path,
      diffSide = "RIGHT",
      subjectType = "FILE",
      line = 1,
      startLine = 1,
      originalLine = 1,
      originalStartLine = 1,
      isOutdated = false,
      isResolved = false,
      comments = { nodes = { { createdAt = created_at } } },
    }
  end

  local function line_thread(id, path, line)
    return {
      id = id,
      path = path,
      diffSide = "RIGHT",
      subjectType = "LINE",
      line = line,
      startLine = line,
      originalLine = line,
      originalStartLine = line,
      isOutdated = false,
      isResolved = false,
      comments = { nodes = { { createdAt = "2026-01-01T00:00:00Z" } } },
    }
  end

  describe("Review:file_threads", function()
    it("lists only the file-level threads of a path, oldest first", function()
      local review = setmetatable({
        threads = {
          T_2 = file_thread("T_2", "lua/foo.lua", "2026-01-02T00:00:00Z"),
          T_1 = file_thread("T_1", "lua/foo.lua", "2026-01-01T00:00:00Z"),
          T_3 = file_thread("T_3", "lua/bar.lua", "2026-01-01T00:00:00Z"),
          T_4 = line_thread("T_4", "lua/foo.lua", 1),
        },
      }, { __index = reviews.Review })
      local ids = vim.tbl_map(function(t)
        return t.id
      end, review:file_threads "lua/foo.lua")
      eq({ "T_1", "T_2" }, ids)
    end)
  end)

  describe("file panel thread_counts", function()
    local file_panel = require "octo.reviews.file-panel"
    local original_get_current_review

    before_each(function()
      original_get_current_review = reviews.get_current_review
      reviews.get_current_review = function()
        return {
          threads = {
            T_1 = file_thread("T_1", "lua/foo.lua", "2026-01-01T00:00:00Z"),
            T_2 = file_thread("T_2", "lua/foo.lua", "2026-01-02T00:00:00Z"),
            T_3 = line_thread("T_3", "lua/foo.lua", 1),
          },
        }
      end
    end)

    after_each(function()
      reviews.get_current_review = original_get_current_review
    end)

    it("counts file-level threads for the marker", function()
      local active, _, _, _, file_level = file_panel.thread_counts "lua/foo.lua"
      eq(3, active)
      eq(2, file_level)
    end)
  end)

  describe("thread_panel.create_thread_buffer", function()
    local thread_panel = require "octo.reviews.thread-panel"
    local writers = require "octo.ui.writers"
    local original_get_current_review
    local original_write_threads
    local rendered

    before_each(function()
      _G.octo_buffers = _G.octo_buffers or {}
      rendered = nil
      original_get_current_review = reviews.get_current_review
      original_write_threads = writers.write_threads
      reviews.get_current_review = function()
        return { id = "R_1" }
      end
      writers.write_threads = function(_, threads)
        rendered = vim.tbl_map(function(t)
          return t.id
        end, threads)
      end
    end)

    after_each(function()
      reviews.get_current_review = original_get_current_review
      writers.write_threads = original_write_threads
      local bufnr = vim.fn.bufnr "octo://o/r/review/R_1/threads/RIGHT/lua/foo.lua:FILE"
      if bufnr ~= -1 then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("does not share a buffer with line 1 threads", function()
      local buffer = thread_panel.create_thread_buffer(
        { file_thread("T_1", "lua/foo.lua", "2026-01-01T00:00:00Z") },
        "o/r",
        1,
        "RIGHT",
        "lua/foo.lua"
      )
      eq("octo://o/r/review/R_1/threads/RIGHT/lua/foo.lua:FILE", vim.api.nvim_buf_get_name(buffer.bufnr))
    end)

    it("rebuilds the buffer so new file-level threads are listed", function()
      local first = file_thread("T_1", "lua/foo.lua", "2026-01-01T00:00:00Z")
      local second = file_thread("T_2", "lua/foo.lua", "2026-01-02T00:00:00Z")
      thread_panel.create_thread_buffer({ first }, "o/r", 1, "RIGHT", "lua/foo.lua")
      thread_panel.create_thread_buffer({ first, second }, "o/r", 1, "RIGHT", "lua/foo.lua")
      eq({ "T_1", "T_2" }, rendered)
    end)

    it("keeps an unsaved draft", function()
      local first = file_thread("T_1", "lua/foo.lua", "2026-01-01T00:00:00Z")
      local buffer = thread_panel.create_thread_buffer({ first }, "o/r", 1, "RIGHT", "lua/foo.lua")
      -- thread buffers are acwrite once configured, scratch buffers ignore `modified`
      vim.bo[buffer.bufnr].buftype = "acwrite"
      vim.bo[buffer.bufnr].modified = true
      rendered = nil
      local again = thread_panel.create_thread_buffer({ first }, "o/r", 1, "RIGHT", "lua/foo.lua")
      eq(buffer.bufnr, again.bufnr)
      eq(nil, rendered)
    end)
  end)

  describe("OctoBuffer:do_add_new_thread", function()
    local original_get_current_review
    local original_graphql
    local captured
    local level

    before_each(function()
      captured = nil
      level = "PR"
      original_get_current_review = reviews.get_current_review
      original_graphql = gh.api.graphql
      reviews.get_current_review = function()
        return {
          layout = {
            get_current_file = function()
              return { path = "lua/foo.lua" }
            end,
          },
          get_level = function()
            return level
          end,
        }
      end
      gh.api.graphql = function(opts)
        captured = opts
      end
    end)

    after_each(function()
      reviews.get_current_review = original_get_current_review
      gh.api.graphql = original_graphql
    end)

    local function metadata(subject_type)
      return {
        reviewId = "R_1",
        body = "file comment",
        path = "lua/foo.lua",
        diffSide = "RIGHT",
        snippetStartLine = 3,
        snippetEndLine = 5,
        subjectType = subject_type,
      }
    end

    it("sends subjectType FILE without line anchors", function()
      OctoBuffer.do_add_new_thread({}, metadata "FILE")
      eq(mutations.add_pull_request_review_thread, captured.query)
      eq({
        pullRequestReviewId = "R_1",
        body = "file comment",
        path = "lua/foo.lua",
        subjectType = "FILE",
      }, captured.F.input)
    end)

    it("uses the thread mutation for file comments at commit level too", function()
      level = "COMMIT"
      OctoBuffer.do_add_new_thread({}, metadata "FILE")
      eq(mutations.add_pull_request_review_thread, captured.query)
      eq("FILE", captured.F.input.subjectType)
    end)

    it("keeps line anchors for line-level threads", function()
      OctoBuffer.do_add_new_thread({}, metadata "LINE")
      eq({
        pullRequestReviewId = "R_1",
        body = "file comment",
        path = "lua/foo.lua",
        side = "RIGHT",
        startLine = 3,
        line = 5,
      }, captured.F.input)
    end)
  end)
end)
