---@diagnostic disable
local logins = require "octo.logins"

-- Mock the logins module to avoid external dependencies
logins.format_author = function(author)
  if author == vim.NIL then
    return vim.NIL
  end
  return author
end

-- Helper to create mock ReviewRequestedEvent
local function make_review_requested(actor_login, reviewer_login, timestamp)
  return {
    __typename = "ReviewRequestedEvent",
    actor = { login = actor_login },
    requestedReviewer = reviewer_login ~= nil and { login = reviewer_login } or vim.NIL,
    createdAt = timestamp or "2024-01-01T10:00:00Z",
  }
end

-- Helper to create mock ReviewRequestRemovedEvent
local function make_review_request_removed(actor_login, reviewer_login, timestamp)
  return {
    __typename = "ReviewRequestRemovedEvent",
    actor = { login = actor_login },
    requestedReviewer = reviewer_login ~= nil and { login = reviewer_login } or vim.NIL,
    createdAt = timestamp or "2024-01-01T10:00:00Z",
  }
end

-- Helper to extract text from chunks (ignore highlights)
local function chunks_to_text(chunks)
  local text = ""
  for _, chunk in ipairs(chunks) do
    text = text .. chunk[1]
  end
  return text
end

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

describe("Review Requested Events", function()
  local build_review_requested_event_chunks
  local build_review_request_removed_event_chunks

  before_each(function()
    vim.g.octo_viewer = "viewer"

    package.loaded["octo.config"] = {
      values = {
        use_timeline_icons = false,
        timeline_marker = "•",
        timeline_indent = 2,
      },
    }

    package.loaded["octo.ui.writers"] = nil
    local writers = require "octo.ui.writers"
    build_review_requested_event_chunks = writers.build_review_requested_event_chunks
    build_review_request_removed_event_chunks = writers.build_review_request_removed_event_chunks
  end)

  describe("build_review_requested_event_chunks", function()
    describe("single reviewer", function()
      it("one reviewer emits one line with 'from X'", function()
        local events = { make_review_requested("alice", "bob") }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        assert.matches("alice", text)
        assert.matches("requested a review", text)
        assert.matches("from", text)
        assert.matches("bob", text)
      end)
    end)

    describe("self-request", function()
      it("self-request emits 'self-requested a review' with no 'from'", function()
        local events = { make_review_requested("alice", "alice") }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        assert.matches("alice", text)
        assert.matches("self%-requested a review", text)
        assert.is_nil(text:match " from ")
      end)

      it("self-request + others emits two separate lines", function()
        local events = {
          make_review_requested("alice", "alice"),
          make_review_requested("alice", "bob"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(2, #builders)
        local self_text = find_builder(builders, "self%-requested")
        local other_text = find_builder(builders, "from bob")
        assert.is_not_nil(self_text, "should have self-requested line")
        assert.is_not_nil(other_text, "should have 'from bob' line")
        -- self line must not mention bob
        assert.is_nil(self_text:match "bob")
      end)
    end)

    describe("multiple reviewers, same actor", function()
      it("two reviewers: 'from X and Y' (no Oxford comma)", function()
        local events = {
          make_review_requested("alice", "bob"),
          make_review_requested("alice", "charlie"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        assert.matches("bob", text)
        assert.matches(" and ", text)
        assert.matches("charlie", text)
        assert.is_nil(text:match ", and ")
      end)

      it("three reviewers: 'from X, Y and Z'", function()
        local events = {
          make_review_requested("alice", "bob"),
          make_review_requested("alice", "charlie"),
          make_review_requested("alice", "dave"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        assert.matches("bob", text)
        assert.matches("charlie", text)
        assert.matches("dave", text)
        assert.matches(", ", text)
        assert.matches(" and ", text)
        assert.is_nil(text:match ", and ")
      end)

      it("groups events with different timestamps from same actor", function()
        local events = {
          make_review_requested("alice", "bob", "2024-01-01T10:00:00Z"),
          make_review_requested("alice", "charlie", "2024-01-01T10:00:01Z"),
          make_review_requested("alice", "dave", "2024-01-01T10:00:02Z"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        assert.matches("bob", text)
        assert.matches("charlie", text)
        assert.matches("dave", text)
      end)
    end)

    describe("multiple actors", function()
      it("two different actors produce separate lines", function()
        local events = {
          make_review_requested("alice", "bob"),
          make_review_requested("charlie", "dave"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(2, #builders)
        assert.is_not_nil(find_builder(builders, "alice"))
        assert.is_not_nil(find_builder(builders, "charlie"))
      end)

      it("actor order is first-seen", function()
        local events = {
          make_review_requested("alice", "bob"),
          make_review_requested("charlie", "dave"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.matches("alice", builder_to_text(builders[1]))
        assert.matches("charlie", builder_to_text(builders[2]))
      end)

      it("different actors requesting same reviewer stay on separate lines", function()
        local events = {
          make_review_requested("alice", "bob"),
          make_review_requested("charlie", "bob"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(2, #builders)
      end)
    end)

    describe("deduplication", function()
      it("same reviewer requested twice only appears once", function()
        local events = {
          make_review_requested("alice", "bob", "2024-01-01T10:00:00Z"),
          make_review_requested("alice", "bob", "2024-01-01T10:00:01Z"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        local _, count = text:gsub("bob", "")
        assert.equals(1, count)
      end)
    end)

    describe("nil requestedReviewer", function()
      it("nil reviewer produces no 'from' clause", function()
        local events = { make_review_requested("alice", nil) }
        local builders = build_review_requested_event_chunks(events, "viewer")
        -- no reviewer at all — self_requested=false, reviewer_list empty → no builders
        assert.equals(0, #builders)
      end)

      it("one nil and one real reviewer still renders the real one", function()
        local events = {
          make_review_requested("alice", nil),
          make_review_requested("alice", "bob"),
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        local text = builder_to_text(builders[1])
        assert.matches("bob", text)
      end)
    end)

    describe("edge cases", function()
      it("empty list returns no builders", function()
        local builders = build_review_requested_event_chunks({}, "viewer")
        assert.equals(0, #builders)
      end)

      it("reviewer with team name (no login)", function()
        local events = {
          {
            __typename = "ReviewRequestedEvent",
            actor = { login = "alice" },
            requestedReviewer = { name = "my-team" },
            createdAt = "2024-01-01T10:00:00Z",
          },
        }
        local builders = build_review_requested_event_chunks(events, "viewer")
        assert.equals(1, #builders)
        assert.matches("my%-team", builder_to_text(builders[1]))
      end)
    end)

    describe("viewer highlighting", function()
      it("viewer as actor gets OctoUserViewer highlight", function()
        local events = { make_review_requested("viewer", "bob") }
        local builders = build_review_requested_event_chunks(events, "viewer")
        local chunks = builders[1]:build()
        local found = false
        for _, chunk in ipairs(chunks) do
          if chunk[1] == "viewer" and chunk[2] == "OctoUserViewer" then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)

      it("viewer as reviewer gets OctoUserViewer highlight", function()
        local events = { make_review_requested("alice", "viewer") }
        local builders = build_review_requested_event_chunks(events, "viewer")
        local chunks = builders[1]:build()
        local found = false
        for _, chunk in ipairs(chunks) do
          if chunk[1] == "viewer" and chunk[2] == "OctoUserViewer" then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)
    end)
  end)

  describe("build_review_request_removed_event_chunks", function()
    it("single removal emits 'removed a review request from X'", function()
      local events = { make_review_request_removed("alice", "bob") }
      local builders = build_review_request_removed_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("alice", text)
      assert.matches("removed a review request", text)
      assert.matches("from", text)
      assert.matches("bob", text)
    end)

    it("two removals by same actor: 'from X and Y'", function()
      local events = {
        make_review_request_removed("alice", "bob"),
        make_review_request_removed("alice", "charlie"),
      }
      local builders = build_review_request_removed_event_chunks(events, "viewer")
      assert.equals(1, #builders)
      local text = builder_to_text(builders[1])
      assert.matches("bob", text)
      assert.matches(" and ", text)
      assert.matches("charlie", text)
      assert.is_nil(text:match ", and ")
    end)

    it("two different actors produce separate lines", function()
      local events = {
        make_review_request_removed("alice", "bob"),
        make_review_request_removed("charlie", "dave"),
      }
      local builders = build_review_request_removed_event_chunks(events, "viewer")
      assert.equals(2, #builders)
      assert.is_not_nil(find_builder(builders, "alice"))
      assert.is_not_nil(find_builder(builders, "charlie"))
    end)

    it("empty list returns no builders", function()
      local builders = build_review_request_removed_event_chunks({}, "viewer")
      assert.equals(0, #builders)
    end)
  end)
end)
