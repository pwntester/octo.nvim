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

-- Find a builder whose text matches a pattern
local function find_builder(builders, pattern)
  for _, builder in ipairs(builders) do
    local text = builder_to_text(builder)
    if text:match(pattern) then
      return text
    end
  end
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

  describe("self-assignment", function()
    it("pure self-assign emits one line", function()
      local events = {
        make_assigned_event("alice", "alice"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("self%-assigned this", text)
      assert.is_nil(text:match "assigned alice") -- should not say "assigned alice"
    end)

    it("pure self-unassign emits one line", function()
      local events = {
        make_unassigned_event("alice", "alice"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("removed their assignment", text)
    end)

    it("self-assign + assign others emits two separate lines", function()
      local events = {
        make_assigned_event("alice", "alice"),
        make_assigned_event("alice", "bob"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(2, #builders)
      local self_text = find_builder(builders, "self%-assigned")
      local other_text = find_builder(builders, "assigned bob")
      assert.is_not_nil(self_text, "should have self-assigned line")
      assert.is_not_nil(other_text, "should have assigned bob line")
      -- self-assigned line should NOT mention bob
      assert.is_nil(self_text:match "bob")
    end)

    it("self-unassign + unassign others emits two separate lines", function()
      local events = {
        make_unassigned_event("alice", "alice"),
        make_unassigned_event("alice", "bob"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(2, #builders)
      local self_text = find_builder(builders, "removed their assignment")
      local other_text = find_builder(builders, "unassigned bob")
      assert.is_not_nil(self_text, "should have removed their assignment line")
      assert.is_not_nil(other_text, "should have unassigned bob line")
    end)
  end)

  describe("assigning others", function()
    it("single assignee", function()
      local events = {
        make_assigned_event("alice", "bob"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("assigned", text)
      assert.matches("bob", text)
    end)

    it("two assignees joined with 'and'", function()
      local events = {
        make_assigned_event("alice", "bob"),
        make_assigned_event("alice", "charlie"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("bob", text)
      assert.matches(" and ", text)
      assert.matches("charlie", text)
      -- no Oxford comma
      assert.is_nil(text:match ", and ")
    end)

    it("three assignees: X, Y and Z", function()
      local events = {
        make_assigned_event("alice", "bob"),
        make_assigned_event("alice", "charlie"),
        make_assigned_event("alice", "dave"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("bob", text)
      assert.matches("charlie", text)
      assert.matches("dave", text)
      assert.matches(", ", text)
      assert.matches(" and ", text)
      assert.is_nil(text:match ", and ")
    end)
  end)

  describe("unassigning others", function()
    it("single unassignee", function()
      local events = {
        make_unassigned_event("alice", "bob"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("unassigned", text)
      assert.matches("bob", text)
    end)

    it("two unassignees joined with 'and'", function()
      local events = {
        make_unassigned_event("alice", "bob"),
        make_unassigned_event("alice", "charlie"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("unassigned", text)
      assert.matches("bob", text)
      assert.matches(" and ", text)
      assert.matches("charlie", text)
    end)
  end)

  describe("mixed assign and unassign", function()
    it("assign one, unassign another: two separate lines", function()
      local events = {
        make_assigned_event("alice", "bob"),
        make_unassigned_event("alice", "charlie"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(2, #builders)
      local assign_text = find_builder(builders, "assigned bob")
      local unassign_text = find_builder(builders, "unassigned charlie")
      assert.is_not_nil(assign_text)
      assert.is_not_nil(unassign_text)
    end)
  end)

  describe("multiple actors", function()
    it("two different actors produce separate builders", function()
      local events = {
        make_assigned_event("alice", "bob"),
        make_assigned_event("charlie", "dave"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(2, #builders)
      assert.is_not_nil(find_builder(builders, "alice"))
      assert.is_not_nil(find_builder(builders, "charlie"))
    end)

    it("actor order is first-seen", function()
      local events = {
        make_assigned_event("alice", "bob"),
        make_assigned_event("charlie", "dave"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(2, #builders)
      assert.matches("alice", builder_to_text(builders[1]))
      assert.matches("charlie", builder_to_text(builders[2]))
    end)

    it("different actors requesting same assignee stay separate", function()
      local events = {
        make_assigned_event("alice", "bob"),
        make_assigned_event("charlie", "bob"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(2, #builders)
    end)
  end)

  describe("deduplication", function()
    it("same assignee assigned twice only appears once", function()
      local events = {
        make_assigned_event("alice", "bob", "2024-01-01T10:00:00Z"),
        make_assigned_event("alice", "bob", "2024-01-01T10:00:01Z"),
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      local _, count = text:gsub("bob", "")
      assert.equals(1, count)
    end)
  end)

  describe("viewer highlighting", function()
    it("viewer as actor gets OctoUserViewer highlight", function()
      local events = { make_assigned_event("viewer", "bob") }
      local builders = build_assignment_event_chunks(events, "viewer")
      local chunks = builders[1]:build()
      local found = false
      for _, chunk in ipairs(chunks) do
        if chunk[1] == "viewer" then
          assert.equals("OctoUserViewer", chunk[2])
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("viewer as assignee gets OctoUserViewer highlight", function()
      local events = { make_assigned_event("alice", "viewer") }
      local builders = build_assignment_event_chunks(events, "viewer")
      local chunks = builders[1]:build()
      local found = false
      for _, chunk in ipairs(chunks) do
        if chunk[1] == "viewer" then
          assert.equals("OctoUserViewer", chunk[2])
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("edge cases", function()
    it("empty list returns no builders", function()
      local builders = build_assignment_event_chunks({}, "viewer")
      assert.equals(0, #builders)
    end)

    it("nil actor is skipped gracefully", function()
      local events = {
        {
          __typename = "AssignedEvent",
          actor = vim.NIL,
          assignee = { login = "bob" },
          createdAt = "2024-01-01T10:00:00Z",
        },
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(0, #builders)
    end)

    it("assignee with name but no login", function()
      local events = {
        {
          __typename = "AssignedEvent",
          actor = { login = "alice" },
          assignee = { name = "Some Team" },
          createdAt = "2024-01-01T10:00:00Z",
        },
      }
      local builders = build_assignment_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      assert.matches("Some Team", builder_to_text(builders[1]))
    end)
  end)
end)
