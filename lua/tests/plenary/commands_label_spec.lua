---@diagnostic disable
local eq = assert.are.same

describe("label commands:", function()
  local commands
  local captured
  local originals

  local function capture()
    captured = nil
  end

  before_each(function()
    commands = require "octo.commands"
    originals = {
      add_label = commands.add_label,
      remove_label = commands.remove_label,
      create_label = commands.create_label,
    }
    capture()

    commands.add_label = function(label)
      captured = label
    end
    commands.remove_label = function(label)
      captured = label
    end
    commands.create_label = function(label)
      captured = label
    end
  end)

  after_each(function()
    commands.add_label = originals.add_label
    commands.remove_label = originals.remove_label
    commands.create_label = originals.create_label
  end)

  it("joins label names split on whitespace for remove", function()
    commands.octo("label", "remove", "Needs", "Triage")
    eq("Needs Triage", captured)
  end)

  it("strips quotes around a label name for remove", function()
    -- the arguments arrive as typed on the command line
    commands.octo("label", "remove", '"Needs', 'Triage"')
    eq("Needs Triage", captured)
  end)

  it("strips single quotes around a label name for remove", function()
    commands.octo("label", "remove", "'Needs", "Triage'")
    eq("Needs Triage", captured)
  end)

  it("joins label names split on whitespace for add", function()
    commands.octo("label", "add", "Needs", "Triage")
    eq("Needs Triage", captured)
  end)

  it("joins label names split on whitespace for create", function()
    commands.octo("label", "create", "Needs", "Triage")
    eq("Needs Triage", captured)
  end)

  it("passes a single word label through untouched", function()
    commands.octo("label", "remove", "bug")
    eq("bug", captured)
  end)

  it("falls back to the picker when no label is given", function()
    commands.octo("label", "remove")
    eq(nil, captured)
  end)
end)
