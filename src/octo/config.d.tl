require("octo.model.octo")

local record M
  record config
    enum Picker
      "fzf-lua"
      "telescope"
      "vim-clap"
    end
    picker: Picker

    default_remote: {string}
    reaction_viewer_hint_icon: string
    user_icon: string
    comment_icon: string
    outdated_icon: string
    resolved_icon: string
    timeline_marker: string
    timeline_indent: string
    right_bubble_delimiter: string
    left_bubble_delimiter: string
    github_hostname: string
    git_hosts: {string:RepoHostType}
    snippet_context_lines: integer

    record FilePanel
      size: integer
      use_icons: boolean
    end
    file_panel: FilePanel

    record Colors
      white: string
      grey: string
      black: string
      red: string
      dark_red: string
      green: string
      dark_green: string
      yellow: string
      dark_yellow: string
      blue: string
      dark_blue: string
      purple: string
    end
    colors: Colors

    record Mappings
      record IssueMappings
        close_issue: string
        reopen_issue: string
        list_issues: string
        reload: string
        open_in_browser: string
        copy_url: string
        add_assignee: string
        remove_assignee: string
        create_label: string
        add_label: string
        remove_label: string
        goto_issue: string
        add_comment: string
        delete_comment: string
        next_comment: string
        prev_comment: string
        react_hooray: string
        react_heart: string
        react_eyes: string
        react_thumbs_up: string
        react_thumbs_down: string
        react_rocket: string
        react_laugh: string
        react_confused: string
      end
      issue: IssueMappings

      record PullRequestMappings
        checkout_pr: string
        merge_pr: string
        squash_and_merge_pr: string
        list_commits: string
        list_changed_files: string
        show_pr_diff: string
        add_reviewer: string
        remove_reviewer: string
        close_issue: string
        reopen_issue: string
        list_issues: string
        reload: string
        open_in_browser: string
        copy_url: string
        goto_file: string
        add_assignee: string
        remove_assignee: string
        create_label: string
        add_label: string
        remove_label: string
        goto_issue: string
        add_comment: string
        delete_comment: string
        next_comment: string
        prev_comment: string
        react_hooray: string
        react_heart: string
        react_eyes: string
        react_thumbs_up: string
        react_thumbs_down: string
        react_rocket: string
        react_laugh: string
        react_confused: string
      end
      pull_request: PullRequestMappings

      record ReviewThreadMappings
        goto_issue: string
        add_comment: string
        add_suggestion: string
        delete_comment: string
        next_comment: string
        prev_comment: string
        select_next_entry: string
        select_prev_entry: string
        react_hooray: string
        react_heart: string
        react_eyes: string
        react_thumbs_up: string
        react_thumbs_down: string
        react_rocket: string
        react_laugh: string
        react_confused: string
        close_review_tab: string
      end
      review_thread: ReviewThreadMappings

      record RepoMappings
      end
      repo: RepoMappings

      record SubmitWinMappings
        close_review_win: string
        approve_review: string
        comment_review: string
        request_changes: string
      end
      submit_win: SubmitWinMappings

      record ReviewDiffMappings
        add_review_comment: string
        add_review_suggestion: string
        select_next_entry: string
        select_prev_entry: string
        focus_files: string
        toggle_files: string
        next_thread: string
        prev_thread: string
        close_review_tab: string
        toggle_viewed: string
      end
      review_diff: ReviewDiffMappings

      record FilePanelMappings
        next_entry: string
        prev_entry: string
        select_entry: string
        refresh_files: string
        select_next_entry: string
        select_prev_entry: string
        focus_files: string
        toggle_files: string
        close_review_tab: string
        toggle_viewed: string
      end
      file_panel: FilePanelMappings
    end
    mappings: Mappings
  end

  get_config: function(): config
  setup: function(user_config: any)
end

return M
