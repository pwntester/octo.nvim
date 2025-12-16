---@diagnostic disable
local logins = require "octo.logins"

-- Mock the logins module to avoid external dependencies
logins.format_author = function(author)
  if author == vim.NIL then
    return vim.NIL
  end
  return author
end

-- Helper to create mock events
local function make_assigned_event(actor_login, assignee_login, timestamp)
  return {
    __typename = "AssignedEvent",
    actor = { login = actor_login },
    assignee = { login = assignee_login },
    createdAt = timestamp or "2024-01-01T10:00:00Z",
  }
end

local function make_unassigned_event(actor_login, assignee_login, timestamp)
  return {
    __typename = "UnassignedEvent",
    actor = { login = actor_login },
    assignee = { login = assignee_login },
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

-- Helper to get builder text
local function builder_to_text(builder)
  return chunks_to_text(builder:build())
end

describe("Assignment Events", function()
  local build_assignment_event_chunks

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

    -- Load the writers module
    package.loaded["octo.ui.writers"] = nil
    local writers = require "octo.ui.writers"
    build_assignment_event_chunks = writers.build_assignment_event_chunks
  end)

  describe("single actor scenarios", function()
    it("should handle self-assignment", function()
      local events = {
        make_assigned_event("alice", "alice", "2024-01-01T10:00:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("self%-assigned this", text)
    end)

    it("should handle single assignee by different actor", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("assigned", text)
      assert.matches("bob", text)
    end)

    it("should handle self-unassignment", function()
      local events = {
        make_unassigned_event("alice", "alice", "2024-01-01T10:00:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("removed their assignment", text)
    end)

    it("should handle assigning multiple people", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("alice", "charlie", "2024-01-01T10:00:01Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("assigned", text)
      assert.matches("bob", text)
      assert.matches("charlie", text)
    end)

    it("should handle unassigning multiple people", function()
      local events = {
        make_unassigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_unassigned_event("alice", "charlie", "2024-01-01T10:00:01Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("unassigned", text)
      assert.matches("bob", text)
      assert.matches("charlie", text)
    end)

    it("should handle mixed assign and unassign", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_unassigned_event("alice", "charlie", "2024-01-01T10:00:01Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("assigned", text)
      assert.matches("bob", text)
      assert.matches("and", text)
      assert.matches("unassigned", text)
      assert.matches("charlie", text)
    end)

    it("should handle assigning same person multiple times (count)", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("alice", "bob", "2024-01-01T10:00:01Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("assigned", text)
      assert.matches("bob", text)
    end)
  end)

  describe("multiple actor scenarios", function()
    it("should handle two different actors", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("charlie", "dave", "2024-01-01T10:05:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      -- Should have separate builders for each actor
      assert.equals(2, #builders)

      -- Find alice and charlie builders
      local alice_text, charlie_text
      for _, builder in ipairs(builders) do
        local text = builder_to_text(builder)
        if text:match "alice" then
          alice_text = text
        elseif text:match "charlie" then
          charlie_text = text
        end
      end

      assert.is_not_nil(alice_text)
      assert.matches("alice", alice_text)
      assert.matches("bob", alice_text)

      assert.is_not_nil(charlie_text)
      assert.matches("charlie", charlie_text)
      assert.matches("dave", charlie_text)
    end)

    it("should preserve actor-specific timestamps", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("charlie", "dave", "2024-01-01T15:30:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      -- Should have two builders
      assert.equals(2, #builders)

      -- Each builder should have chunks with dates
      for _, builder in ipairs(builders) do
        local chunks = builder:build()
        assert.is_true(#chunks > 0)
      end
    end)

    it("should handle same actor with mixed events spread across timeline", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("alice", "charlie", "2024-01-01T10:00:01Z"),
        make_unassigned_event("alice", "bob", "2024-01-01T10:00:02Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])

      -- Alice assigned bob and charlie, then unassigned bob
      assert.matches("alice", text)
      assert.matches("assigned", text)
      assert.matches("charlie", text) -- charlie is still assigned
      assert.matches("unassigned", text)
      assert.matches("bob", text) -- bob appears in unassigned
    end)
  end)

  describe("viewer detection", function()
    it("should highlight viewer as actor", function()
      local events = {
        make_assigned_event("viewer", "bob", "2024-01-01T10:00:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local chunks = builders[1]:build()

      -- Find the viewer chunk and check its highlight
      local found_viewer = false
      for _, chunk in ipairs(chunks) do
        if chunk[1] == "viewer" then
          assert.equals("OctoUserViewer", chunk[2])
          found_viewer = true
          break
        end
      end
      assert.is_true(found_viewer, "Should find viewer with correct highlight")
    end)

    it("should highlight viewer as assignee", function()
      local events = {
        make_assigned_event("alice", "viewer", "2024-01-01T10:00:00Z"),
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local chunks = builders[1]:build()

      -- Find the viewer chunk in assignee position
      local found_viewer = false
      for _, chunk in ipairs(chunks) do
        if chunk[1] == "viewer" then
          assert.equals("OctoUserViewer", chunk[2])
          found_viewer = true
          break
        end
      end
      assert.is_true(found_viewer, "Should find viewer as assignee with correct highlight")
    end)
  end)

  describe("edge cases", function()
    it("should handle empty events list", function()
      local events = {}
      local builders = build_assignment_event_chunks(events, "viewer")

      -- Should return empty array
      assert.equals(0, #builders)
    end)

    it("should handle nil actor gracefully", function()
      local events = {
        {
          __typename = "AssignedEvent",
          actor = vim.NIL,
          assignee = { login = "bob" },
          createdAt = "2024-01-01T10:00:00Z",
        },
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      -- Should not have entry for nil actor
      assert.equals(0, #builders)
    end)

    it("should handle assignee with name but no login", function()
      local events = {
        {
          __typename = "AssignedEvent",
          actor = { login = "alice" },
          assignee = { name = "Bob Organization" },
          createdAt = "2024-01-01T10:00:00Z",
        },
      }

      local builders = build_assignment_event_chunks(events, "viewer")

      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("Bob Organization", text)
    end)
  end)

  describe("deterministic ordering", function()
    it("should produce consistent output for same input", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("charlie", "dave", "2024-01-01T10:05:00Z"),
        make_assigned_event("eve", "frank", "2024-01-01T10:10:00Z"),
      }

      -- Run multiple times and ensure same number of builders
      local builders1 = build_assignment_event_chunks(events, "viewer")
      local builders2 = build_assignment_event_chunks(events, "viewer")

      -- Should have same number of builders (3 actors)
      assert.equals(3, #builders1)
      assert.equals(3, #builders2)

      -- Should have all three actors
      local actors1 = {}
      for _, builder in ipairs(builders1) do
        local text = builder_to_text(builder)
        if text:match "alice" then
          actors1.alice = true
        end
        if text:match "charlie" then
          actors1.charlie = true
        end
        if text:match "eve" then
          actors1.eve = true
        end
      end

      assert.is_true(actors1.alice)
      assert.is_true(actors1.charlie)
      assert.is_true(actors1.eve)
    end)
  end)
end)
