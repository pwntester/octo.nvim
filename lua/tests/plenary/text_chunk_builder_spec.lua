---@diagnostic disable
local TextChunkBuilder = require "octo.ui.text-chunk-builder"

describe("TextChunkBuilder", function()
  describe("basic text operations", function()
    it("should create empty builder", function()
      local builder = TextChunkBuilder:new()
      assert.are.same({}, builder:build())
    end)

    it("should add text with highlight", function()
      local builder = TextChunkBuilder:new()
      builder:text("hello", "Highlight")
      assert.are.same({ { "hello", "Highlight" } }, builder:build())
    end)

    it("should add text without highlight", function()
      local builder = TextChunkBuilder:new()
      builder:text "hello"
      assert.are.same({ { "hello", "" } }, builder:build())
    end)

    it("should chain multiple text calls", function()
      local builder = TextChunkBuilder:new()
      builder:text("hello", "Hl1"):text("world", "Hl2")
      assert.are.same({
        { "hello", "Hl1" },
        { "world", "Hl2" },
      }, builder:build())
    end)

    it("should use append for vt[#vt + 1] pattern", function()
      local builder = TextChunkBuilder:new()
      builder:append("a", "hl1"):append("b", "hl2")
      assert.are.same({
        { "a", "hl1" },
        { "b", "hl2" },
      }, builder:build())
    end)
  end)

  describe("timeline markers", function()
    it("should add timeline marker with icons enabled", function()
      local builder = TextChunkBuilder:new()
      builder:timeline_marker "commit"
      local chunks = builder:build()
      -- Icon should be present from config
      assert.is_true(#chunks > 0)
      assert.is_string(chunks[1][1])
    end)

    it("should add timeline marker without icon name", function()
      local builder = TextChunkBuilder:new()
      builder:timeline_marker()
      local chunks = builder:build()
      -- Should have marker and EVENT: label when icons disabled
      assert.is_true(#chunks >= 1)
    end)

    it("should add indented marker", function()
      local builder = TextChunkBuilder:new()
      builder:indented_marker(2)
      local chunks = builder:build()
      assert.is_true(#chunks > 0)
      -- Should contain indentation (check if string starts with spaces)
      local has_indent = chunks[1][1]:match "^%s+" ~= nil
      assert.is_true(has_indent)
    end)
  end)

  describe("user methods", function()
    it("should add user with plain style", function()
      local builder = TextChunkBuilder:new()
      builder:user_plain("testuser", true)
      local chunks = builder:build()
      assert.are.same({ { "testuser", "OctoUserViewer" } }, chunks)
    end)

    it("should add user with plain style (not viewer)", function()
      local builder = TextChunkBuilder:new()
      builder:user_plain("otheruser", false)
      local chunks = builder:build()
      assert.are.same({ { "otheruser", "OctoUser" } }, chunks)
    end)

    it("should add actor with viewer detection", function()
      vim.g.octo_viewer = "testuser"
      local builder = TextChunkBuilder:new()
      builder:actor { login = "testuser" }
      local chunks = builder:build()
      assert.are.same("testuser", chunks[1][1])
      assert.are.same("OctoUserViewer", chunks[1][2])
    end)

    it("should add actor (not viewer)", function()
      vim.g.octo_viewer = "testuser"
      local builder = TextChunkBuilder:new()
      builder:actor { login = "otheruser" }
      local chunks = builder:build()
      assert.are.same("otheruser", chunks[1][1])
      assert.are.same("OctoUser", chunks[1][2])
    end)
  end)

  describe("heading and date methods", function()
    it("should add heading with default highlight", function()
      local builder = TextChunkBuilder:new()
      builder:heading "merged commit"
      assert.are.same({ { "merged commit", "OctoTimelineItemHeading" } }, builder:build())
    end)

    it("should add heading with custom highlight", function()
      local builder = TextChunkBuilder:new()
      builder:heading("text", "CustomHl")
      assert.are.same({ { "text", "CustomHl" } }, builder:build())
    end)

    it("should format date with default prefix", function()
      local builder = TextChunkBuilder:new()
      builder:date "2024-01-01T00:00:00Z"
      local chunks = builder:build()
      -- Check if starts with space
      local starts_with_space = chunks[1][1]:sub(1, 1) == " "
      assert.is_true(starts_with_space)
      assert.are.same("OctoDate", chunks[1][2])
    end)

    it("should format date with custom prefix", function()
      local builder = TextChunkBuilder:new()
      builder:date("2024-01-01T00:00:00Z", "")
      local chunks = builder:build()
      -- Check if does NOT start with space
      local starts_with_space = chunks[1][1]:sub(1, 1) == " "
      assert.is_false(starts_with_space)
    end)
  end)

  describe("detail methods", function()
    it("should add detail label", function()
      local builder = TextChunkBuilder:new()
      builder:detail_label "Status"
      assert.are.same({ { "Status: ", "OctoDetailsLabel" } }, builder:build())
    end)

    it("should add detail value", function()
      local builder = TextChunkBuilder:new()
      builder:detail_value "open"
      assert.are.same({ { "open", "OctoDetailsValue" } }, builder:build())
    end)

    it("should chain detail label and value", function()
      local builder = TextChunkBuilder:new()
      builder:detail_label("Status"):detail_value "open"
      assert.are.same({
        { "Status: ", "OctoDetailsLabel" },
        { "open", "OctoDetailsValue" },
      }, builder:build())
    end)

    it("should write detail line to array", function()
      local details = {}
      TextChunkBuilder:new():detail_label("Test"):detail_value("value"):write_detail_line(details)
      assert.are.same(1, #details)
      assert.are.same(2, #details[1])
    end)
  end)

  describe("conditional methods", function()
    it("should add text when condition is true", function()
      local builder = TextChunkBuilder:new()
      builder:when(true, "yes", "Hl1"):when(false, "no", "Hl2")
      assert.are.same(1, #builder:build())
      assert.are.same("yes", builder:build()[1][1])
    end)

    it("should not add text when condition is false", function()
      local builder = TextChunkBuilder:new()
      builder:when(false, "no", "Hl")
      assert.are.same(0, #builder:build())
    end)

    it("should execute callback when condition is true", function()
      local builder = TextChunkBuilder:new()
      builder:when_fn(true, function(b)
        b:text("inside", "Hl")
      end)
      assert.are.same({ { "inside", "Hl" } }, builder:build())
    end)

    it("should not execute callback when condition is false", function()
      local builder = TextChunkBuilder:new()
      builder:when_fn(false, function(b)
        b:text("inside", "Hl")
      end)
      assert.are.same({}, builder:build())
    end)

    it("should add lock icon when viewer cannot update", function()
      local builder = TextChunkBuilder:new()
      builder:lock_icon(false)
      assert.are.same({ { " ", "OctoRed" } }, builder:build())
    end)

    it("should not add lock icon when viewer can update", function()
      local builder = TextChunkBuilder:new()
      builder:lock_icon(true)
      assert.are.same({}, builder:build())
    end)
  end)

  describe("utility methods", function()
    it("should add single space", function()
      local builder = TextChunkBuilder:new()
      builder:space()
      assert.are.same({ { " ", "" } }, builder:build())
    end)

    it("should add multiple spaces", function()
      local builder = TextChunkBuilder:new()
      builder:space(3)
      assert.are.same({ { "   ", "" } }, builder:build())
    end)

    it("should extend with raw chunks", function()
      local builder = TextChunkBuilder:new()
      builder:extend { { "chunk1", "hl1" }, { "chunk2", "hl2" } }
      assert.are.same(2, #builder:build())
    end)

    it("should report correct length", function()
      local builder = TextChunkBuilder:new()
      builder:text("a"):text("b"):text "c"
      assert.are.same(3, builder:length())
    end)

    it("should detect if empty", function()
      local builder = TextChunkBuilder:new()
      assert.is_true(builder:is_empty())
      builder:text "test"
      assert.is_false(builder:is_empty())
    end)
  end)

  describe("builder reuse", function()
    it("should reset builder", function()
      local builder = TextChunkBuilder:new()
      builder:text("hello"):reset():text "world"
      assert.are.same(1, #builder:build())
      assert.are.same("world", builder:build()[1][1])
    end)

    it("should clone builder", function()
      local builder = TextChunkBuilder:new():text "original"
      local cloned = builder:clone()
      cloned:text "cloned"
      assert.are.same(1, #builder:build())
      assert.are.same(2, #cloned:build())
    end)

    it("should allow independent modification after clone", function()
      local builder = TextChunkBuilder:new():text("a", "h1")
      local cloned = builder:clone()
      builder:text("b", "h2")
      cloned:text("c", "h3")
      assert.are.same(2, #builder:build())
      assert.are.same(2, #cloned:build())
      assert.are.same("b", builder:build()[2][1])
      assert.are.same("c", cloned:build()[2][1])
    end)
  end)

  describe("complex chaining", function()
    it("should build timeline event", function()
      local builder = TextChunkBuilder:new()
      builder
        :timeline_marker("merged")
        :actor({ login = "testuser" })
        :heading(" merged commit ")
        :text("abc123", "OctoDetailsLabel")
        :date "2024-01-01T00:00:00Z"
      local chunks = builder:build()
      -- Should have multiple chunks
      assert.is_true(#chunks >= 4)
    end)

    it("should build detail line with label", function()
      local builder = TextChunkBuilder:new()
      builder:detail_label("Labels"):text("bug", "Label1"):text("enhancement", "Label2")
      local chunks = builder:build()
      assert.are.same(3, #chunks)
      assert.are.same("Labels: ", chunks[1][1])
    end)
  end)
end)
