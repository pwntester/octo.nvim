local context = require "octo.context"
local reviews = require "octo.reviews"
local utils = require "octo.utils"

--- Create a picker to select from a list of callable options
---@param options table<string, fun()>
---@param prompt string
local create_options_picker = function(options, prompt)
  vim.ui.select(vim.fn.keys(options), {
    prompt = prompt,
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice == nil then
      return
    end

    return options[choice]()
  end)
end

local create_reaction_picker = function()
  ---@type {name: string, value: string}[]
  local reactions = {}
  for name, value in pairs(utils.reaction_map) do
    reactions[#reactions + 1] = { name = name, value = value }
  end

  vim.ui.select(reactions, {
    prompt = "Select a reaction:",
    format_item = function(item)
      return item.value .. "(" .. utils.title_case(utils.remove_underscore(item.name)) .. ")"
    end,
  }, function(choice)
    if choice == nil then
      return
    end
    require("octo.commands").reaction_action(choice.name)
  end)
end

return {
  repo_options = function()
    local commands = require("octo.commands").commands

    local options = {
      ["Open in Browser"] = commands.repo.browser,
      ["View Contribution Guidelines"] = function()
        local buffer = utils.get_current_buffer()
        ---@type string?
        local repo
        if buffer and buffer.repo then
          repo = buffer.repo
        else
          repo = utils.get_remote_name()
        end

        if repo == nil then
          utils.error "Could not determine repository"
          return
        end

        utils.display_contributing_file(repo)
      end,
      ["Create Issue"] = commands.issue.create,
      ["Create Discussion"] = commands.discussion.create,
    }
    create_options_picker(options, "Select an option:")
  end,
  pr_options = function()
    local commands = require("octo.commands").commands
    local options = {
      ["Get Review from Copilot"] = commands.pr.copilot,
      ["Get Workflow Runs"] = commands.pr.runs,
      ["View Check Status"] = commands.pr.checks,
      ["Checkout PR"] = commands.pr.checkout,
      ["List Commits"] = commands.pr.commits,
      ["List File Changes"] = commands.pr.changes,
      ["View diff"] = commands.pr.diff,
      ["Close PR"] = commands.pr.close,
      ["Reopen PR"] = commands.pr.reopen,
      ["Merge PR"] = commands.pr.merge,
      ["Mark as Ready for Review"] = commands.pr.ready,
      ["Update Base Branch"] = commands.pr.update,
      ["Copy URL"] = commands.pr.url,
      ["Open in Browser"] = commands.pr.browser,
      ["Reload PR buffer"] = commands.pr.reload,
      ["Squash and Merge PR"] = function()
        commands.pr.merge "squash"
      end,
      ["Start Review"] = commands.review.start,
      ["Resume Review"] = commands.review.resume,
      ["Add Label(s)"] = commands.label.add,
      ["Remove Label(s)"] = commands.label.remove,
      ["Add Milestone"] = commands.milestone.add,
      ["Remove Milestone"] = commands.milestone.remove,
      ["Copy SHA"] = commands.pr.sha,
      ["Add Reviewer"] = commands.reviewer.add,
      ["Remove Reviewer"] = commands.reviewer.remove,
      ["Resolve Thread"] = commands.thread.resolve,
      ["Unresolve Thread"] = commands.thread.unresolve,
      ["Add Assignee"] = commands.assignee.add,
      ["Remove Assignee"] = commands.assignee.remove,
      ["Add ProjectV2 Card"] = commands.cardv2.set,
      ["Remove ProjectV2 Card"] = commands.cardv2.remove,
      ["Add Comment"] = commands.comment.add,
      ["Add Reply"] = commands.comment.reply,
      ["Delete Comment"] = commands.comment.delete,
      ["View Repo"] = context.within_issue_or_pr(function(buffer)
        commands.repo.view(buffer.repo)
      end),
      ["React"] = create_reaction_picker,
    }
    create_options_picker(options, "Select an option:")
  end,
  issue_options = function()
    local commands = require("octo.commands").commands

    local options = {
      ["Add Label(s)"] = commands.label.add,
      ["Remove Label(s)"] = commands.label.remove,
      ["Reload Issue"] = commands.issue.reload,
      ["Reopen Issue"] = commands.issue.reopen,
      ["Close Issue"] = commands.issue.close,
      ["Open in Browser"] = commands.issue.browser,
      ["Copy URL"] = commands.issue.url,
      ["Add Type"] = commands.type.add,
      ["Remove Type"] = commands.type.remove,
      ["Add Milestone"] = commands.milestone.add,
      ["Remove Milestone"] = commands.milestone.remove,
      ["Edit Parent Issue"] = commands.parent.edit,
      ["Add Parent Issue"] = commands.parent.add,
      ["Remove Parent Issue"] = commands.parent.remove,
      ["Assign to Copilot"] = commands.issue.copilot,
      ["Develop Issue"] = commands.issue.develop,
      ["Pin Issue"] = commands.issue.pin,
      ["Unpin Issue"] = commands.issue.unpin,
      ["Add Assignee"] = commands.assignee.add,
      ["Remove Assignee"] = commands.assignee.remove,
      ["Add ProjectV2 Card"] = commands.cardv2.set,
      ["Remove ProjectV2 Card"] = commands.cardv2.remove,
      ["Add Comment"] = commands.comment.add,
      ["Delete Comment"] = commands.comment.delete,
      ["View Repo"] = context.within_issue_or_pr(function(buffer)
        commands.repo.view(buffer.repo)
      end),
      ["React"] = create_reaction_picker,
    }
    create_options_picker(options, "Select an option:")
  end,
  create_issue = function()
    require("octo.commands").create_issue()
  end,
  create_discussion = function()
    local buffer = utils.get_current_buffer()

    ---@type string?
    local repo
    if buffer and buffer.repo then
      repo = buffer.repo
    else
      repo = utils.get_remote_name()
    end

    if repo == nil then
      utils.error "Could not determine repository"
      return
    end

    require("octo.discussions").create { repo = repo }
  end,
  contributing_guidelines = function()
    local buffer = utils.get_current_buffer()
    ---@type string?
    local repo
    if buffer and buffer.repo then
      repo = buffer.repo
    else
      repo = utils.get_remote_name()
    end

    if repo == nil then
      utils.error "Could not determine repository"
      return
    end

    utils.display_contributing_file(repo)
  end,
  close_issue = function()
    require("octo.commands").change_state "CLOSED"
  end,
  reopen_issue = function()
    require("octo.commands").change_state "OPEN"
  end,
  list_issues = context.within_octo_buffer(function(buffer)
    require("octo.picker").issues { repo = buffer.repo }
  end),
  checkout_pr = function()
    require("octo.commands").commands.pr.checkout()
  end,
  list_commits = function()
    require("octo.picker").commits()
  end,
  review_commits = function()
    local current_review = reviews.get_current_review()
    if not current_review then
      return
    end
    require("octo.picker").review_commits(function(right, left)
      current_review:focus_commit(right, left)
    end)
  end,
  list_changed_files = function()
    require("octo.picker").changed_files()
  end,
  show_pr_diff = function()
    require("octo.commands").show_pr_diff()
  end,
  merge_pr = function()
    require("octo.commands").merge_pr "merge"
  end,
  merge_pr_queue = function()
    require("octo.commands").merge_pr("merge", "queue")
  end,
  squash_and_merge_pr = function()
    require("octo.commands").merge_pr "squash"
  end,
  squash_and_merge_queue = function()
    require("octo.commands").merge_pr("squash", "queue")
  end,
  rebase_and_merge_pr = function()
    require("octo.commands").merge_pr "rebase"
  end,
  rebase_and_merge_queue = function()
    require("octo.commands").merge_pr("rebase", "queue")
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
  copy_sha = function()
    require("octo.commands").copy_sha()
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
  add_reply = function()
    require("octo.commands").add_pr_issue_or_review_thread_comment_reply()
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
  select_next_unviewed_entry = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:select_next_unviewed_file()
    end
  end,
  select_prev_unviewed_entry = function()
    local layout = reviews.get_current_layout()
    if layout then
      layout:select_prev_unviewed_file()
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
