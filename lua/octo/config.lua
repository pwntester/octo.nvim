local M = {}

M.defaults = {
  date_format = "%Y %b %d %I:%M %p %Z";
  default_remote = {"upstream", "origin"};
  reaction_viewer_hint_icon = "";
  user_icon = " ";
  timeline_marker = "";
  timeline_indent = "2";
  right_bubble_delimiter = "";
  left_bubble_delimiter = "";
  github_hostname = "";
  snippet_context_lines = 4;
  file_panel = {
    size = 10,
    use_icons = true
  },
  mappings = {
    issue = {
      close_issue = "<space>ic",
      reopen_issue = "<space>io",
      list_issues = "<space>il",
      reload = "<C-r>",
      open_in_browser = "<C-o>",
      add_assignee = "<space>aa",
      remove_assignee = "<space>ad",
      add_label = "<space>la",
      remove_label = "<space>ld",
      goto_issue = "<space>gi",
      add_comment = "<space>ca",
      delete_comment = "<space>cd",
      next_comment = "]c",
      prev_comment = "[c",
      react_hooray = "<space>rp",
      react_heart = "<space>rh",
      react_eyes = "<space>re",
      react_thumbs_up = "<space>r+",
      react_thumbs_down = "<space>r-",
      react_rocket = "<space>rr",
      react_laugh = "<space>rl",
      react_confused = "<space>rc",

    },
    pull_request = {
      checkout_pr = "<space>po",
      merge_pr = "<space>pm",
      list_commits = "<space>pc",
      list_changed_files = "<space>pf",
      show_pr_diff = "<space>pd",
      add_reviewer = "<space>va",
      remove_reviewer = "<space>vd",
      close_issue = "<space>ic",
      reopen_issue = "<space>io",
      list_issues = "<space>il",
      reload = "<C-r>",
      open_in_browser = "<C-o>",
      add_assignee = "<space>aa",
      remove_assignee = "<space>ad",
      add_label = "<space>la",
      remove_label = "<space>ld",
      goto_issue = "<space>gi",
      add_comment = "<space>ca",
      delete_comment = "<space>cd",
      next_comment = "]c",
      prev_comment = "[c",
      react_hooray = "<space>rp",
      react_heart = "<space>rh",
      react_eyes = "<space>re",
      react_thumbs_up = "<space>r+",
      react_thumbs_down = "<space>r-",
      react_rocket = "<space>rr",
      react_laugh = "<space>rl",
      react_confused = "<space>rc",
    },
    review_thread = {
      goto_issue = "<space>gi",
      add_comment = "<space>ca",
      add_suggestion = "<space>sa",
      delete_comment = "<space>cd",
      next_comment = "]c",
      prev_comment = "[c",
      select_next_entry = "]q",
      select_prev_entry = "[q",
      react_hooray = "<space>rp",
      react_heart = "<space>rh",
      react_eyes = "<space>re",
      react_thumbs_up = "<space>r+",
      react_thumbs_down = "<space>r-",
      react_rocket = "<space>rr",
      react_laugh = "<space>rl",
      react_confused = "<space>rc",
      close_review_tab = "<C-c>",
    },
    review_diff = {
      add_review_comment = "<space>ca",
      add_review_suggestion = "<space>sa",
      select_next_entry = "]q",
      select_prev_entry = "[q",
      focus_files = "<leader>e",
      toggle_files = "<leader>b",
      next_thread = "]t",
      prev_thread = "[t",
      close_review_tab = "<C-c>",
    },
    submit_win = {
      close_review_win = "<C-c>",
      approve_review = "<C-a>",
      comment_review = "<C-m>",
      request_changes = "<C-r>",
    },
    file_panel = {
      next_entry = "j",
      prev_entry = "k",
      select_entry = "<cr>",
      refresh_files = "R",
      select_next_entry = "]q",
      select_prev_entry = "[q",
      focus_files = "<leader>e",
      toggle_files = "<leader>b",
      close_review_tab = "<C-c>",
    }
  }
}

M._config = M.defaults

function M.get_config()
  return M._config
end

function M.setup(user_config)
  user_config = user_config or {}
  M._config = require"octo.util".tbl_deep_clone(M.defaults)
  require"octo.util".tbl_soft_extend(M._config, user_config)

  M._config.file_panel = vim.tbl_deep_extend(
    "force", M.defaults.file_panel, user_config.file_panel or {}
  )

  -- If the user provides key bindings: use only the user bindings.
  if user_config.mappings then
    M._config.mappings.issue = (
      user_config.mappings.issue or M._config.mappings.issue
    )
    M._config.mappings.pull_request = (
      user_config.mappings.pull_request or M._config.mappings.pull_request
    )
    M._config.mappings.review_thread = (
      user_config.mappings.review_thread or M._config.mappings.review_thread
    )
    M._config.mappings.review = (
      user_config.mappings.review or M._config.mappings.review
    )
    M._config.mappings.file_panel = (
      user_config.mappings.file_panel or M._config.mappings.file_panel
    )
  end
end

return M
