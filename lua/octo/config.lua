local vim = vim
local M = {}

---@alias OctoMappingsWindow "issue" | "pull_request" | "review_thread" | "submit_win" | "review_diff" | "file_panel" | "repo" | "notification"
---@alias OctoMappingsList { [string]: table}
---@alias OctoPickers "telescope" | "fzf-lua"
---@alias OctoSplit "right" | "left"

---@class OctoPickerConfig
---@field use_emojis boolean
---@field mappings table

---@class OctoConfigColors
---@field white string
---@field grey string
---@field black string
---@field red string
---@field dark_red string
---@field green string
---@field dark_green string
---@field yellow string
---@field dark_yellow string
---@field blue string
---@field dark_blue string
---@field purple string

---@class OctoConfigFilePanel
---@field size number
---@field use_icons boolean

---@class OctoConfigUi
---@field use_signcolumn boolean
---@field use_statuscolumn boolean
---@field use_foldtext boolean

---@class OctoConfigIssues
---@field order_by OctoConfigOrderBy

---@class OctoConfigReviews
---@field auto_show_threads boolean
---@field focus OctoSplit

---@class OctoConfigDiscussions
---@field order_by OctoConfigOrderBy

---@class OctoConfigNotifications
---@field current_repo_only boolean

---@class OctoConfigPR
---@field order_by OctoConfigOrderBy
---@field always_select_remote_on_create boolean

---@class OctoConfigOrderBy
---@field field string
---@field direction "ASC" | "DESC"

---@class OctoMissingScopeConfig
---@field projects_v2 boolean

---@class OctoConfig Octo configuration settings
---@field picker OctoPickers
---@field picker_config OctoPickerConfig
---@field default_remote table
---@field default_merge_method string
---@field default_delete_branch boolean
---@field ssh_aliases {[string]:string}
---@field reaction_viewer_hint_icon string
---@field commands table
---@field users string
---@field user_icon string
---@field ghost_icon string
---@field comment_icon string
---@field outdated_icon string
---@field resolved_icon string
---@field timeline_marker string
---@field timeline_indent string
---@field right_bubble_delimiter string
---@field left_bubble_delimiter string
---@field github_hostname string
---@field use_local_fs boolean
---@field enable_builtin boolean
---@field snippet_context_lines number
---@field gh_cmd string
---@field gh_env table
---@field timeout number
---@field default_to_projects_v2 boolean
---@field suppress_missing_scope OctoMissingScopeConfig
---@field ui OctoConfigUi
---@field issues OctoConfigIssues
---@field reviews OctoConfigReviews
---@field pull_requests OctoConfigPR
---@field file_panel OctoConfigFilePanel
---@field colors OctoConfigColors
---@field mappings { [OctoMappingsWindow]: OctoMappingsList}
---@field mappings_disable_default boolean
---@field discussions OctoConfigDiscussions
---@field notifications OctoConfigNotifications

--- Returns the default octo config values
---@return OctoConfig
function M.get_default_values()
  return {
    picker = "telescope",
    picker_config = {
      use_emojis = false,
      mappings = {
        open_in_browser = { lhs = "<C-b>", desc = "open issue in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        checkout_pr = { lhs = "<C-o>", desc = "checkout pull request" },
        merge_pr = { lhs = "<C-r>", desc = "merge pull request" },
      },
    },
    default_remote = { "upstream", "origin" },
    default_merge_method = "commit",
    default_delete_branch = false,
    ssh_aliases = {},
    reaction_viewer_hint_icon = " ",
    commands = {},
    users = "search",
    user_icon = " ",
    ghost_icon = "󰊠 ",
    comment_icon = "▎",
    outdated_icon = "󰅒 ",
    resolved_icon = " ",
    timeline_marker = " ",
    timeline_indent = "2",
    right_bubble_delimiter = "",
    left_bubble_delimiter = "",
    github_hostname = "",
    use_local_fs = false,
    enable_builtin = false,
    snippet_context_lines = 4,
    gh_cmd = "gh",
    gh_env = {},
    timeout = 5000,
    default_to_projects_v2 = false,
    suppress_missing_scope = {
      projects_v2 = false,
    },
    ui = {
      use_signcolumn = false,
      use_statuscolumn = true,
      use_foldtext = true,
    },
    issues = {
      order_by = {
        field = "CREATED_AT",
        direction = "DESC",
      },
    },
    discussions = {
      order_by = {
        field = "CREATED_AT",
        direction = "DESC",
      },
    },
    notifications = {
      current_repo_only = false,
    },
    reviews = {
      auto_show_threads = true,
      focus = "right",
    },
    pull_requests = {
      order_by = {
        field = "CREATED_AT",
        direction = "DESC",
      },
      always_select_remote_on_create = false,
    },
    file_panel = {
      size = 10,
      use_icons = true,
    },
    colors = {
      white = "#ffffff",
      grey = "#2A354C",
      black = "#000000",
      red = "#fdb8c0",
      dark_red = "#da3633",
      green = "#acf2bd",
      dark_green = "#238636",
      yellow = "#d3c846",
      dark_yellow = "#735c0f",
      blue = "#58A6FF",
      dark_blue = "#0366d6",
      purple = "#6f42c1",
    },
    mappings_disable_default = false,
    mappings = {
      issue = {
        close_issue = { lhs = "<localleader>ic", desc = "close issue" },
        reopen_issue = { lhs = "<localleader>io", desc = "reopen issue" },
        list_issues = { lhs = "<localleader>il", desc = "list open issues on same repo" },
        reload = { lhs = "<C-r>", desc = "reload issue" },
        open_in_browser = { lhs = "<C-b>", desc = "open issue in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        add_assignee = { lhs = "<localleader>aa", desc = "add assignee" },
        remove_assignee = { lhs = "<localleader>ad", desc = "remove assignee" },
        create_label = { lhs = "<localleader>lc", desc = "create label" },
        add_label = { lhs = "<localleader>la", desc = "add label" },
        remove_label = { lhs = "<localleader>ld", desc = "remove label" },
        goto_issue = { lhs = "<localleader>gi", desc = "navigate to a local repo issue" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 🎉 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove ❤️ reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 👀 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 👍 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 👎 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove 🚀 reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 😄 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 😕 reaction" },
      },
      pull_request = {
        checkout_pr = { lhs = "<localleader>po", desc = "checkout PR" },
        merge_pr = { lhs = "<localleader>pm", desc = "merge commit PR" },
        squash_and_merge_pr = { lhs = "<localleader>psm", desc = "squash and merge PR" },
        rebase_and_merge_pr = { lhs = "<localleader>prm", desc = "rebase and merge PR" },
        list_commits = { lhs = "<localleader>pc", desc = "list PR commits" },
        list_changed_files = { lhs = "<localleader>pf", desc = "list PR changed files" },
        show_pr_diff = { lhs = "<localleader>pd", desc = "show PR diff" },
        add_reviewer = { lhs = "<localleader>va", desc = "add reviewer" },
        remove_reviewer = { lhs = "<localleader>vd", desc = "remove reviewer request" },
        close_issue = { lhs = "<localleader>ic", desc = "close PR" },
        reopen_issue = { lhs = "<localleader>io", desc = "reopen PR" },
        list_issues = { lhs = "<localleader>il", desc = "list open issues on same repo" },
        reload = { lhs = "<C-r>", desc = "reload PR" },
        open_in_browser = { lhs = "<C-b>", desc = "open PR in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        goto_file = { lhs = "gf", desc = "go to file" },
        add_assignee = { lhs = "<localleader>aa", desc = "add assignee" },
        remove_assignee = { lhs = "<localleader>ad", desc = "remove assignee" },
        create_label = { lhs = "<localleader>lc", desc = "create label" },
        add_label = { lhs = "<localleader>la", desc = "add label" },
        remove_label = { lhs = "<localleader>ld", desc = "remove label" },
        goto_issue = { lhs = "<localleader>gi", desc = "navigate to a local repo issue" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 🎉 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove ❤️ reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 👀 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 👍 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 👎 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove 🚀 reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 😄 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 😕 reaction" },
        review_start = { lhs = "<localleader>vs", desc = "start a review for the current PR" },
        review_resume = { lhs = "<localleader>vr", desc = "resume a pending review for the current PR" },
        resolve_thread = { lhs = "<localleader>rt", desc = "resolve PR thread" },
        unresolve_thread = { lhs = "<localleader>rT", desc = "unresolve PR thread" },
      },
      review_thread = {
        goto_issue = { lhs = "<localleader>gi", desc = "navigate to a local repo issue" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        add_suggestion = { lhs = "<localleader>sa", desc = "add suggestion" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        select_next_entry = { lhs = "]q", desc = "move to next changed file" },
        select_prev_entry = { lhs = "[q", desc = "move to previous changed file" },
        select_first_entry = { lhs = "[Q", desc = "move to first changed file" },
        select_last_entry = { lhs = "]Q", desc = "move to last changed file" },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 🎉 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove ❤️ reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 👀 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 👍 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 👎 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove 🚀 reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 😄 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 😕 reaction" },
        resolve_thread = { lhs = "<localleader>rt", desc = "resolve PR thread" },
        unresolve_thread = { lhs = "<localleader>rT", desc = "unresolve PR thread" },
      },
      submit_win = {
        approve_review = { lhs = "<C-a>", desc = "approve review", mode = { "n", "i" } },
        comment_review = { lhs = "<C-m>", desc = "comment review", mode = { "n", "i" } },
        request_changes = { lhs = "<C-r>", desc = "request changes review", mode = { "n", "i" } },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab", mode = { "n", "i" } },
      },
      review_diff = {
        submit_review = { lhs = "<localleader>vs", desc = "submit review" },
        discard_review = { lhs = "<localleader>vd", desc = "discard review" },
        add_review_comment = { lhs = "<localleader>ca", desc = "add a new review comment", mode = { "n", "x" } },
        add_review_suggestion = { lhs = "<localleader>sa", desc = "add a new review suggestion", mode = { "n", "x" } },
        focus_files = { lhs = "<localleader>e", desc = "move focus to changed file panel" },
        toggle_files = { lhs = "<localleader>b", desc = "hide/show changed files panel" },
        next_thread = { lhs = "]t", desc = "move to next thread" },
        prev_thread = { lhs = "[t", desc = "move to previous thread" },
        select_next_entry = { lhs = "]q", desc = "move to next changed file" },
        select_prev_entry = { lhs = "[q", desc = "move to previous changed file" },
        select_first_entry = { lhs = "[Q", desc = "move to first changed file" },
        select_last_entry = { lhs = "]Q", desc = "move to last changed file" },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
        toggle_viewed = { lhs = "<localleader><space>", desc = "toggle viewer viewed state" },
        goto_file = { lhs = "gf", desc = "go to file" },
      },
      file_panel = {
        submit_review = { lhs = "<localleader>vs", desc = "submit review" },
        discard_review = { lhs = "<localleader>vd", desc = "discard review" },
        next_entry = { lhs = "j", desc = "move to next changed file" },
        prev_entry = { lhs = "k", desc = "move to previous changed file" },
        select_entry = { lhs = "<cr>", desc = "show selected changed file diffs" },
        refresh_files = { lhs = "R", desc = "refresh changed files panel" },
        focus_files = { lhs = "<localleader>e", desc = "move focus to changed file panel" },
        toggle_files = { lhs = "<localleader>b", desc = "hide/show changed files panel" },
        select_next_entry = { lhs = "]q", desc = "move to next changed file" },
        select_prev_entry = { lhs = "[q", desc = "move to previous changed file" },
        select_first_entry = { lhs = "[Q", desc = "move to first changed file" },
        select_last_entry = { lhs = "]Q", desc = "move to last changed file" },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
        toggle_viewed = { lhs = "<localleader><space>", desc = "toggle viewer viewed state" },
      },
      notification = {
        read = { lhs = "<localleader>nr", desc = "mark notification as read" },
      },
      repo = {},
    },
  }
end

M.values = M.get_default_values()

---Validates the config
---@return { [string]: string } all error messages emitted during validation
function M.validate_config()
  local config = M.values

  ---@type { [string]: string }
  local errors = {}
  local function err(value, msg)
    errors[value] = msg
  end

  ---Checks if a variable is the correct type if not it calls err with an error string
  ---@param value any
  ---@param name string
  ---@param expected_types type | type[]
  local function validate_type(value, name, expected_types)
    if type(expected_types) == "table" then
      if not vim.tbl_contains(expected_types, type(value)) then
        err(
          name,
          string.format(
            "Expected `%s` to be one of types '%s', got '%s'",
            name,
            table.concat(expected_types, ", "),
            type(value)
          )
        )
        return false
      end
      return true
    end

    if type(value) ~= expected_types then
      err(name, string.format("Expected `%s` to be of type '%s', got '%s'", name, expected_types, type(value)))
      return false
    end
    return true
  end

  ---Checks if a variable is one of the allowed string value
  ---@param value any
  ---@param name string
  ---@param expected_strings string[]
  local function validate_string_enum(value, name, expected_strings)
    -- First check that the value is indeed a string
    if validate_type(value, name, "string") then
      -- Then check it matches one of the expected values
      if not vim.tbl_contains(expected_strings, value) then
        err(
          name .. "." .. value,
          string.format(
            "Received '%s', which is not supported! Valid values: %s",
            value,
            table.concat(expected_strings, ", ")
          )
        )
      end
    end
  end

  local function validate_pickers()
    validate_string_enum(config.picker, "picker", { "telescope", "fzf-lua" })

    if not validate_type(config.picker_config, "picker_config", "table") then
      return
    end

    validate_type(config.picker_config.use_emojis, "picker_config.use_emojis", "boolean")
    validate_type(config.picker_config.mappings, "picker_config.mappings", "table")
  end

  local function validate_aliases()
    if not validate_type(config.ssh_aliases, "ssh_aliases", "table") then
      return
    end
    for name, alias in pairs(config.ssh_aliases) do
      validate_type(alias, string.format("ssh_aliases.%s", name), "string")
    end
  end

  local function validate_issues()
    if not validate_type(config.issues, "issues", "table") then
      return
    end
    if validate_type(config.issues.order_by, "issues.order_by", "table") then
      validate_type(config.issues.order_by.field, "issues.order_by.field", "string")
      validate_type(config.issues.order_by.direction, "issues.order_by.direction", "string")
    end
  end

  local function validate_reviews()
    if not validate_type(config.reviews, "reviews", "table") then
      return
    end

    validate_type(config.reviews.auto_show_threads, "reviews.auto_show_threads", "boolean")
    validate_string_enum(config.reviews.focus, "reviews.focus", { "right", "left" })
  end

  local function validate_pull_requests()
    if not validate_type(config.pull_requests, "pull_requests", "table") then
      return
    end
    if validate_type(config.pull_requests.order_by, "pull_requests.order_by", "table") then
      validate_type(config.pull_requests.order_by.field, "pull_requests.order_by.field", "string")
      validate_type(config.pull_requests.order_by.direction, "pull_requests.order_by.direction", "string")
    end
    validate_type(config.pull_requests.always_select_remote_on_create, "always_select_remote_on_create", "boolean")
  end

  local function validate_notifications()
    if not validate_type(config.notifications, "notifications", "table") then
      err("notifications", "Expected notifications to be a table")
      return
    end
    validate_type(config.notifications.current_repo_only, "notifications.current_repo_only", "boolean")
  end

  local function validate_mappings()
    -- TODO(jarviliam): Validate each keymap
    if not validate_type(config.mappings, "mappings", "table") then
      return
    end
  end

  if validate_type(config, "base config", "table") then
    validate_type(config.use_local_fs, "use_local_fs", "boolean")
    validate_type(config.enable_builtin, "enable_builtin", "boolean")
    validate_type(config.snippet_context_lines, "snippet_context_lines", "number")
    validate_type(config.timeout, "timeout", "number")
    validate_type(config.default_to_projects_v2, "default_to_projects_v2", "boolean")
    if validate_type(config.suppress_missing_scope, "supress_missing_scope", "table") then
      validate_type(config.suppress_missing_scope.projects_v2, "supress_missing_scope.projects_v2", "boolean")
    end
    validate_type(config.gh_cmd, "gh_cmd", "string")
    validate_type(config.gh_env, "gh_env", { "table", "function" })
    validate_type(config.reaction_viewer_hint_icon, "reaction_viewer_hint_icon", "string")
    validate_string_enum(config.users, "users", { "search", "mentionable", "assignable" })
    validate_type(config.user_icon, "user_icon", "string")
    validate_type(config.ghost_icon, "ghost_icon", "string")
    validate_type(config.comment_icon, "comment_icon", "string")
    validate_type(config.outdated_icon, "outdated_icon", "string")
    validate_type(config.resolved_icon, "resolved_icon", "string")
    validate_type(config.timeline_marker, "timeline_marker", "string")
    validate_type(config.timeline_indent, "timeline_indent", "string")
    validate_type(config.right_bubble_delimiter, "right_bubble_delimiter", "string")
    validate_type(config.left_bubble_delimiter, "left_bubble_delimiter", "string")
    validate_type(config.github_hostname, "github_hostname", "string")
    if validate_type(config.default_remote, "default_remote", "table") then
      for _, v in ipairs(config.default_remote) do
        validate_type(v, "remote", "string")
      end
    end
    validate_type(config.default_merge_method, "default_merge_method", "string")
    if validate_type(config.ui, "ui", "table") then
      validate_type(config.ui.use_signcolumn, "ui.use_signcolumn", "boolean")
      validate_type(config.ui.use_statuscolumn, "ui.use_statuscolumn", "boolean")
      validate_type(config.ui.use_foldtext, "ui.use_foldtext", "boolean")
    end
    if validate_type(config.colors, "colors", "table") then
      for k, v in pairs(config.colors) do
        validate_type(v, string.format("colors.%s", k), "string")
      end
    end

    validate_issues()
    validate_reviews()
    validate_pull_requests()
    validate_notifications()
    if validate_type(config.file_panel, "file_panel", "table") then
      validate_type(config.file_panel.size, "file_panel.size", "number")
      validate_type(config.file_panel.use_icons, "file_panel.use_icons", "boolean")
    end
    validate_aliases()
    validate_pickers()
    validate_mappings()
  end

  return errors
end

function M.setup(opts)
  if opts ~= nil then
    if opts.mappings_disable_default == true then
      -- clear default mappings before merging user mappings
      M.values.mappings = {
        issue = {},
        pull_request = {},
        review_thread = {},
        submit_win = {},
        review_diff = {},
        file_panel = {},
        repo = {},
      }
    end
    M.values = vim.tbl_deep_extend("force", M.values, opts)
  end
  local config_errs = M.validate_config()
  if vim.tbl_count(config_errs) > 0 then
    local header = "====Octo Configuration Errors===="
    local header_message = {
      "You have a misconfiguration in your octo setup!",
      'Validate that your configuration passed to `require("octo").setup()` is valid!',
    }
    local header_sep = ""
    for _ = 0, string.len(header), 1 do
      header_sep = header_sep .. "-"
    end

    local config_errs_message = {}
    for config_key, err in pairs(config_errs) do
      table.insert(config_errs_message, string.format("Config value: `%s` had error -> %s", config_key, err))
    end
    error(
      string.format(
        "\n%s\n%s\n%s\n%s",
        header,
        table.concat(header_message, "\n"),
        header_sep,
        table.concat(config_errs_message, "\n")
      ),
      vim.log.levels.ERROR
    )
  end
  M.values.ui.use_statuscolumn = M.values.ui.use_statuscolumn and vim.fn.has "nvim-0.9" == 1
  M.values.ui.use_foldtext = M.values.ui.use_foldtext and vim.fn.has "nvim-0.10" == 1
end

return M
