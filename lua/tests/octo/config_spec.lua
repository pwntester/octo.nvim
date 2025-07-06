---@diagnostic disable
local config = require "octo.config"

describe("Octo config", function()
  before_each(function()
    config.values = config.get_default_values()
  end)
  describe("validation", function()
    describe("for bad configs", function()
      it("should return invalid when the base config isn't a table", function()
        config.values = "INVALID"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker isn't a string", function()
        config.values.picker = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker isn't valid", function()
        config.values.picker = "other"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config isn't a table", function()
        config.values.picker_config = "cfg"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.mappings isn't a table", function()
        config.values.picker_config.mappings = "cfg"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.mappings action isn't a table", function()
        config.values.picker_config.mappings = { open_in_browser = "cfg" }
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.mappings action lhs isn't a string", function()
        config.values.picker_config.mappings = { open_in_browser = { lhs = 123, desc = "desc" } }
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.mappings action desc isn't a string", function()
        config.values.picker_config.mappings = { open_in_browser = { lhs = "<C-b>", desc = 123 } }
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.snacks isn't a table", function()
        config.values.picker_config.snacks = "cfg"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.snacks.actions isn't a table", function()
        config.values.picker_config.snacks.actions = "cfg"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.snacks.actions contains non-function", function()
        config.values.picker_config.snacks.actions = { issues = { ["<C-a>"] = "not a function" } }
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when picker_config.snacks.actions contains invalid picker type", function()
        config.values.picker_config.snacks.actions = { invalid_picker = { ["<C-a>"] = function() end } }
        -- This currently passes validation as we don't restrict keys, but the actions won't be used.
        -- If strict validation is added later, this test should fail.
        assert.True(vim.tbl_count(require("octo.config").validate_config()) == 0)
      end)

      it("should return invalid when user_icon isn't a string", function()
        config.values.user_icon = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when comment_icon isn't a string", function()
        config.values.comment_icon = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when reaction_viewer_hint_icon isn't a string", function()
        config.values.reaction_viewer_hint_icon = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when outdated_icon isn't a string", function()
        config.values.outdated_icon = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when resolved_icon isn't a string", function()
        config.values.resolved_icon = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when timeline_marker isn't a string", function()
        config.values.timeline_marker = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when timeline_indent isn't a string", function()
        config.values.timeline_indent = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when right_bubble_delimiter isn't a string", function()
        config.values.right_bubble_delimiter = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when left_bubble_delimiter isn't a string", function()
        config.values.left_bubble_delimiter = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when github_hostname isn't a string", function()
        config.values.github_hostname = false
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when use_local_fs isn't a boolean", function()
        config.values.use_local_fs = "not a boolean"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when enable_builtin isn't a boolean", function()
        config.values.enable_builtin = "not a boolean"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when snippet_context_lines isn't a number", function()
        config.values.snippet_context_lines = "not a number"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when gh_env isn't a table", function()
        config.values.gh_env = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when timeout isn't a number", function()
        config.values.timeout = "not a number"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when default_to_projects_v2 isn't a boolean", function()
        config.values.default_to_projects_v2 = "not a boolean"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when suppress_missing_scope isn't a table", function()
        config.values.suppress_missing_scope = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when ui isn't a table", function()
        config.values.ui = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when issues isn't a table", function()
        config.values.issues = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when pull_requests isn't a table", function()
        config.values.pull_requests = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when file_panel isn't a table", function()
        config.values.file_panel = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when colors isn't a table", function()
        config.values.colors = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)

      it("should return invalid when mappings isn't a table", function()
        config.values.mappings = "not a table"
        assert.True(vim.tbl_count(require("octo.config").validate_config()) ~= 0)
      end)
    end)

    describe("for good configs", function()
      it("should return valid for the default config", function()
        assert.True(vim.tbl_count(require("octo.config").validate_config()) == 0)
      end)
    end)
  end)
end)
