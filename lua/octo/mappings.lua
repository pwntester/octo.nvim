local reviews = require "octo.reviews"
local config = require "octo.config"

return {
  close_issue = function()
    require("octo.commands").change_state "CLOSED"
  end,
  reopen_issue = function()
    require("octo.commands").change_state "OPEN"
  end,
  list_issues = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local buffer = octo_buffers[bufnr]
    local repo = buffer.repo
    if repo then
      require("octo.picker").issues { repo = repo }
    end
  end,
  checkout_pr = function()
    require("octo.commands").commands.pr.checkout()
  end,
  list_commits = function()
    require("octo.picker").commits()
  end,
  list_changed_files = function()
    require("octo.picker").changed_files()
  end,
  show_pr_diff = function()
    require("octo.commands").show_pr_diff()
  end,
  merge_pr = function()
    require("octo.commands").merge_pr "commit"
  end,
  squash_and_merge_pr = function()
    require("octo.commands").merge_pr "squash"
  end,
  rebase_and_merge_pr = function()
    require("octo.commands").merge_pr "rebase"
  end,
  add_reviewer = function()
    require("octo.commands").add_user "reviewer"
  end,
  remove_reviewer = function()
    require("octo.commands").remove_user "reviewer"
  end,
  reload = function()
    require("octo.commands").reload()
  end,
  open_in_browser = function()
    require("octo.navigation").open_in_browser()
  end,
  copy_url = function()
    require("octo.commands").copy_url()
  end,
  create_label = function()
    require("octo.commands").create_label()
  end,
  add_label = function()
    require("octo.commands").add_label()
  end,
  remove_label = function()
    require("octo.commands").remove_label()
  end,
  add_assignee = function()
    require("octo.commands").add_user "assignee"
  end,
  remove_assignee = function()
    require("octo.commands").remove_user "assignee"
  end,
  goto_issue = function()
    require("octo.navigation").go_to_issue()
  end,
  goto_file = function()
    require("octo.navigation").go_to_file()
  end,
  next_comment = function()
    require("octo.navigation").next_comment()
  end,
  prev_comment = function()
    require("octo.navigation").prev_comment()
  end,
  add_comment = function()
    require("octo.commands").add_pr_issue_or_review_thread_comment()
  end,
  add_suggestion = function()
    require("octo.commands").add_suggestion()
  end,
  delete_comment = function()
    require("octo.commands").delete_comment()
  end,
  react_hooray = function()
    require("octo.commands").reaction_action "hooray"
  end,
  react_heart = function()
    require("octo.commands").reaction_action "heart"
  end,
  react_eyes = function()
    require("octo.commands").reaction_action "eyes"
  end,
  react_thumbs_up = function()
    require("octo.commands").reaction_action "+1"
  end,
  react_thumbs_down = function()
    require("octo.commands").reaction_action "-1"
  end,
  react_rocket = function()
    require("octo.commands").reaction_action "rocket"
  end,
  react_laugh = function()
    require("octo.commands").reaction_action "laugh"
  end,
  react_confused = function()
    require("octo.commands").reaction_action "confused"
  end,
  review_start = function()
    reviews.start_review()
  end,
  review_resume = function()
    reviews.resume_review()
  end,
  resolve_thread = function()
    require("octo.commands").resolve_thread()
  end,
  unresolve_thread = function()
    require("octo.commands").unresolve_thread()
  end,
  discard_review = function()
    reviews.discard_review()
  end,
  submit_review = function()
    reviews.submit_review()
  end,
  add_review_comment = function()
    reviews.add_review_comment(false)
  end,
  add_review_suggestion = function()
    reviews.add_review_comment(true)
  end,
  close_review_tab = function()
    local tabpage = vim.api.nvim_get_current_tabpage()
    reviews.close(tabpage)
  end,
  next_thread = function()
    require("octo.reviews.file-panel").next_thread()
  end,
  prev_thread = function()
    require("octo.reviews.file-panel").prev_thread()
  end,
  select_next_entry = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:select_next_file()
    end
  end,
  select_prev_entry = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:select_prev_file()
    end
  end,
  select_first_entry = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:select_first_file()
    end
  end,
  select_last_entry = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:select_last_file()
    end
  end,
  next_entry = function()
    local layout = reviews.get_current_layout()
    if layout and layout.file_panel:is_open() then
      layout.file_panel:highlight_next_file()
    end
  end,
  prev_entry = function()
    local layout = reviews.get_current_layout()
    if layout and layout.file_panel:is_open() then
      layout.file_panel:highlight_prev_file()
    end
  end,
  select_entry = function()
    local layout = reviews.get_current_layout()
    if layout and layout.file_panel:is_open() then
      local file = layout.file_panel:get_file_at_cursor()
      if file then
        layout:set_current_file(file)
      end
    end
  end,
  focus_files = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout.file_panel:focus(true)
    end
  end,
  toggle_files = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout.file_panel:toggle()
    end
  end,
  refresh_files = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:update_files()
    end
  end,
  close_review_win = function()
    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
  end,
  approve_review = function()
    local current_review = reviews.get_current_review()
    if not current_review then
      return
    end
    current_review:submit "APPROVE"
  end,
  comment_review = function()
    local current_review = reviews.get_current_review()
    if not current_review then
      return
    end
    current_review:submit "COMMENT"
  end,
  request_changes = function()
    local current_review = reviews.get_current_review()
    if not current_review then
      return
    end
    current_review:submit "REQUEST_CHANGES"
  end,
  toggle_viewed = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout.file_panel:get_file_at_cursor():toggle_viewed()
    end
  end,
}
