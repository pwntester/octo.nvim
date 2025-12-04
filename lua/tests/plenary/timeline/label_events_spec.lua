---@diagnostic disable
local logins = require "octo.logins"

-- Mock the logins module to avoid external dependencies
logins.format_author = function(author)
  if author == vim.NIL then
    return vim.NIL
  end
  return author
end

-- Helper to create mock labeled events
local function make_labeled_event(actor_login, label_name, label_color, timestamp)
  return {
    __typename = "LabeledEvent",
    actor = { login = actor_login },
    label = { name = label_name, color = label_color },
    createdAt = timestamp or "2024-01-01T10:00:00Z",
  }
end

local function make_unlabeled_event(actor_login, label_name, label_color, timestamp)
  return {
    __typename = "UnlabeledEvent",
    actor = { login = actor_login },
    label = { name = label_name, color = label_color },
    createdAt = timestamp or "2024-01-01T10:00:00Z",
  }
end

-- Helper to extract text from chunks (ignore highlights for readability)
local function chunks_to_text(chunks)
  local text = ""
  for _, chunk in ipairs(chunks) do
    text = text .. chunk[1]
  end
  return text
end

describe("Label Events", function()
  local build_label_event_chunks
  local bufnr

  before_each(function()
    -- Set up viewer
    vim.g.octo_viewer = "viewer"

    -- Mock config
    package.loaded["octo.config"] = {
      values = {
        use_timeline_icons = false,
        timeline_marker = "•",
        timeline_indent = 2,
      },
    }

    -- Mock bubbles module
    package.loaded["octo.ui.bubbles"] = {
      make_label_bubble = function(name, color, opts)
        -- Return chunks in the expected format [string, string][]
        return { { "[" .. name .. "]", "OctoLabel" } }
      end,
    }

    -- Create a test buffer
    bufnr = vim.api.nvim_create_buf(false, true)

    -- Load the writers module
    package.loaded["octo.ui.writers"] = nil
    local writers = require "octo.ui.writers"
    build_label_event_chunks = writers.build_label_event_chunks
  end)

  after_each(function()
    -- Clean up buffer
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("deduplication", function()
    it("should deduplicate identical labeled events by same actor", function()
      local events = {
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
        make_labeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:01Z"),
        make_labeled_event("alice", "tests", "#0000ff", "2024-01-01T10:00:02Z"),
        -- Duplicates
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:03Z"),
        make_labeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:04Z"),
        make_labeled_event("alice", "tests", "#0000ff", "2024-01-01T10:00:05Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      assert.equals(1, #builders, "Should have one builder for alice")
      local text = chunks_to_text(builders[1]:build())

      -- Should only mention each label once
      local _, bug_count = text:gsub("%[bug%]", "")
      assert.equals(1, bug_count, "Label 'bug' should appear only once")

      local _, enhancement_count = text:gsub("%[enhancement%]", "")
      assert.equals(1, enhancement_count, "Label 'enhancement' should appear only once")

      local _, tests_count = text:gsub("%[tests%]", "")
      assert.equals(1, tests_count, "Label 'tests' should appear only once")

      assert.matches("alice", text)
      assert.matches("added", text)
    end)

    it("should deduplicate identical unlabeled events by same actor", function()
      local events = {
        make_unlabeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
        make_unlabeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:01Z"),
        -- Duplicates
        make_unlabeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:02Z"),
        make_unlabeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:03Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      assert.equals(1, #builders, "Should have one builder for alice")
      local text = chunks_to_text(builders[1]:build())

      -- Should only mention each label once
      local _, bug_count = text:gsub("%[bug%]", "")
      assert.equals(1, bug_count, "Label 'bug' should appear only once")

      local _, enhancement_count = text:gsub("%[enhancement%]", "")
      assert.equals(1, enhancement_count, "Label 'enhancement' should appear only once")

      assert.matches("alice", text)
      assert.matches("removed", text)
    end)

    it("should combine labeled and unlabeled events on same line", function()
      local events = {
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
        make_labeled_event("alice", "tests", "#0000ff", "2024-01-01T10:00:01Z"),
        make_unlabeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:02Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      assert.equals(1, #builders, "Should have one builder for alice")
      local text = chunks_to_text(builders[1]:build())

      assert.matches("alice", text)
      assert.matches("added", text)
      assert.matches("%[bug%]", text)
      assert.matches("%[tests%]", text)
      assert.matches("and", text)
      assert.matches("removed", text)
      assert.matches("%[enhancement%]", text)
    end)
  end)

  describe("single actor scenarios", function()
    it("should handle single label addition", function()
      local events = {
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = chunks_to_text(builders[1]:build())

      assert.matches("alice", text)
      assert.matches("added", text)
      assert.matches("%[bug%]", text)
    end)

    it("should handle multiple label additions", function()
      local events = {
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
        make_labeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:01Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = chunks_to_text(builders[1]:build())

      assert.matches("alice", text)
      assert.matches("added", text)
      assert.matches("%[bug%]", text)
      assert.matches("%[enhancement%]", text)
    end)

    it("should handle single label removal", function()
      local events = {
        make_unlabeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = chunks_to_text(builders[1]:build())

      assert.matches("alice", text)
      assert.matches("removed", text)
      assert.matches("%[bug%]", text)
    end)
  end)

  describe("multiple actor scenarios", function()
    it("should handle two different actors adding labels", function()
      local events = {
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
        make_labeled_event("bob", "enhancement", "#00ff00", "2024-01-01T10:05:00Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      -- Should have separate builders for each actor
      assert.equals(2, #builders)

      local alice_text, bob_text
      for _, builder in ipairs(builders) do
        local text = chunks_to_text(builder:build())
        if text:match "alice" then
          alice_text = text
        elseif text:match "bob" then
          bob_text = text
        end
      end

      assert.is_not_nil(alice_text)
      assert.matches("alice", alice_text)
      assert.matches("%[bug%]", alice_text)

      assert.is_not_nil(bob_text)
      assert.matches("bob", bob_text)
      assert.matches("%[enhancement%]", bob_text)
    end)

    it("should not mix labels from different actors", function()
      local events = {
        make_labeled_event("alice", "bug", "#ff0000", "2024-01-01T10:00:00Z"),
        make_labeled_event("alice", "enhancement", "#00ff00", "2024-01-01T10:00:01Z"),
        make_labeled_event("bob", "tests", "#0000ff", "2024-01-01T10:00:02Z"),
      }

      local builders = build_label_event_chunks(events, "viewer")

      -- Should have 2 builders (one for each actor)
      assert.equals(2, #builders, "Should have entries for both actors")
    end)
  end)

  describe("edge cases", function()
    it("should handle empty events list", function()
      local events = {}
      local builders = build_label_event_chunks(events, "viewer")

      -- Should return empty array
      assert.equals(0, #builders)
    end)

    it("should handle nil actor gracefully", function()
      local events = {
        {
          __typename = "LabeledEvent",
          actor = vim.NIL,
          label = { name = "bug", color = "#ff0000" },
          createdAt = "2024-01-01T10:00:00Z",
        },
      }

      local builders = build_label_event_chunks(events, "viewer")

      -- Should not have entry for nil actor
      assert.equals(0, #builders)
    end)
  end)
end)
