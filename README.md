# :octopus: Octo.nvim

<p align="center">
	GitHub in NeoVim.
</p>


<p align="center">
    <a href="https://github.com/pwntester/octo.nvim"><img
            src="https://img.shields.io/github/repo-size/pwntester/octo.nvim"
            alt="GitHub repository size"/></a>
    <a href="https://github.com/pwntester/octo.nvim/issues"><img
            src="https://img.shields.io/github/issues/pwntester/octo.nvim"
            alt="Issues"/></a>
    <a href="https://github.com/pwntester/octo.nvim/blob/master/LICENSE"><img
            src="https://img.shields.io/github/license/pwntester/octo.nvim"
            alt="License"/></a><br />
    <a href="https://saythanks.io/to/alvaro%40pwntester.com"><img
            src="https://img.shields.io/badge/say-thanks-modal.svg"
            alt="Say thanks"/></a>    
    <a href="https://github.com/pwntester/octo.nvim/commits/main"><img
			         src="https://img.shields.io/github/last-commit/pwntester/octo.nvim"
			         alt="Latest commit"/></a>
    <a href="https://github.com/pwntester/octo.nvim/stargazers"><img
            src="https://img.shields.io/github/stars/pwntester/octo.nvim"
            alt="Repository's starts"/></a>
</p>

<img width="2099" alt="image" src="https://user-images.githubusercontent.com/125701/117284893-9f281200-ae67-11eb-9d66-ab3f127f23ce.png">
<p align="center">
	Issue/Pull Request listing
</p>

<img width="2116" alt="image" src="https://user-images.githubusercontent.com/125701/117285783-aef42600-ae68-11eb-9073-a7e52eb2f1a9.png">
<p align="center">
	Issue/Pull Request buffer
</p>

<img width="2120" alt="image" src="https://user-images.githubusercontent.com/125701/117286381-6be68280-ae69-11eb-9319-0e633f2b5390.png">
<p align="center">
	Label picking
</p>

# TL;DR
<div style="text-align: justify">
Edit and review GitHub issues and pull requests from the comfort of your favorite editor.
</div>

# 🌲 Table of Contents
* [✨ Features](#-features)
* [⚡️ Requirements](#-requirements)
* [📦 Installation](#-installation)
* [⚙️ Configuration](#-configuration)
* [🚀 Usage](#-usage)
* [🤖 Commands](#-commands)
* [🔥 Examples](#-examples)
* [📋 PR review](#-pr-review)
* [🍞 Completion](#-completion)
* [🎨 Colors](#-colors)
* [🙋 FAQ](#-faq)
* [✋ Contributing](#-contributing)
* [📜 License](#-license)

## ✨ Features

- Edit GitHub issues and PRs
- Add/Modify/Delete comments
- Add/Remove label, reactions, assignees, project cards, reviewers, etc.
- Add Review PRs

## ⚡️Requirements

- Install [GitHub CLI](https://cli.github.com/)
- Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
 
## 📦 Installation 

Use your favourite plugin manager to install it. eg:

```
use {'pwntester/octo.nvim', config=function()
  require"octo".setup()
end}
```

## ⚙️ Configuration

```
use {'pwntester/octo.nvim', config=function()
  require"octo".setup({
  date_format = "%Y %b %d %I:%M %p %Z";    -- date format
  default_remote = {"upstream", "origin"}; -- order to try remotes
  reaction_viewer_hint_icon = "";         -- marker for user reactions
  user_icon = " ";                        -- user icon
  timeline_marker = "";                   -- timeline marker
  timeline_indent = "2";                   -- timeline indentation
  right_bubble_delimiter = "";            -- Bubble delimiter
  left_bubble_delimiter = "";             -- Bubble delimiter
  github_hostname = "";                    -- GitHub Enterprise host
  snippet_context_lines = 4;               -- number or lines around commented lines
  file_panel = {
    size = 10,                             -- changed files panel rows
    use_icons = true                       -- use web-devicons in file panel
  },
  mappings = {
    issue = {
      close_issue = "<space>ic",           -- close issue
      reopen_issue = "<space>io",          -- reopen issue
      list_issues = "<space>il",           -- list open issues on same repo
      reload = "<C-r>",                    -- reload issue
      open_in_browser = "<C-o>",           -- open issue in browser
      add_assignee = "<space>aa",          -- add assignee
      remove_assignee = "<space>ad",       -- remove assignee
      add_label = "<space>la",             -- add label
      remove_label = "<space>ld",          -- remove label
      goto_issue = "<space>gi",            -- navigate to a local repo issue
      add_comment = "<space>ca",           -- add comment
      delete_comment = "<space>cd",        -- delete comment
      next_comment = "]c",                 -- go to next comment
      prev_comment = "[c",                 -- go to previous comment
      react_hooray = "<space>rp",          -- add/remove 🎉 reaction
      react_heart = "<space>rh",           -- add/remove ❤️ reaction
      react_eyes = "<space>re",            -- add/remove 👀 reaction
      react_thumbs_up = "<space>r+",       -- add/remove 👍 reaction
      react_thumbs_down = "<space>r-",     -- add/remove 👎 reaction
      react_rocket = "<space>rr",          -- add/remove 🚀 reaction
      react_laugh = "<space>rl",           -- add/remove 😄 reaction
      react_confused = "<space>rc",        -- add/remove 😕 reaction
    },
    pull_request = {
      checkout_pr = "<space>po",           -- checkout PR
      merge_pr = "<space>pm",              -- merge PR
      list_commits = "<space>pc",          -- list PR commits
      list_changed_files = "<space>pf",    -- list PR changed files
      show_pr_diff = "<space>pd",          -- show PR diff
      add_reviewer = "<space>va",          -- add reviewer
      remove_reviewer = "<space>vd",       -- remove reviewer request
      close_issue = "<space>ic",           -- close PR
      reopen_issue = "<space>io",          -- reopen PR
      list_issues = "<space>il",           -- list open issues on same repo
      reload = "<C-r>",                    -- reload PR
      open_in_browser = "<C-o>",           -- open PR in browser
      add_assignee = "<space>aa",          -- add assignee
      remove_assignee = "<space>ad",       -- remove assignee
      add_label = "<space>la",             -- add label
      remove_label = "<space>ld",          -- remove label
      goto_issue = "<space>gi",            -- navigate to a local repo issue
      add_comment = "<space>ca",           -- add comment
      delete_comment = "<space>cd",        -- delete comment
      next_comment = "]c",                 -- go to next comment
      prev_comment = "[c",                 -- go to previous comment
      react_hooray = "<space>rp",          -- add/remove 🎉 reaction
      react_heart = "<space>rh",           -- add/remove ❤️ reaction
      react_eyes = "<space>re",            -- add/remove 👀 reaction
      react_thumbs_up = "<space>r+",       -- add/remove 👍 reaction
      react_thumbs_down = "<space>r-",     -- add/remove 👎 reaction
      react_rocket = "<space>rr",          -- add/remove 🚀 reaction
      react_laugh = "<space>rl",           -- add/remove 😄 reaction
      react_confused = "<space>rc",        -- add/remove 😕 reaction
    },
    review_thread = {
      goto_issue = "<space>gi",            -- navigate to a local repo issue
      add_comment = "<space>ca",           -- add comment
      add_suggestion = "<space>sa",        -- add suggestion
      delete_comment = "<space>cd",        -- delete comment
      next_comment = "]c",                 -- go to next comment
      prev_comment = "[c",                 -- go to previous comment
      select_next_entry = "]q",            -- move to previous changed file
      select_prev_entry = "[q",            -- move to next changed file
      close_review_tab = "<C-c>",          -- close review tab
      react_hooray = "<space>rp",          -- add/remove 🎉 reaction
      react_heart = "<space>rh",           -- add/remove ❤️ reaction
      react_eyes = "<space>re",            -- add/remove 👀 reaction
      react_thumbs_up = "<space>r+",       -- add/remove 👍 reaction
      react_thumbs_down = "<space>r-",     -- add/remove 👎 reaction
      react_rocket = "<space>rr",          -- add/remove 🚀 reaction
      react_laugh = "<space>rl",           -- add/remove 😄 reaction
      react_confused = "<space>rc",        -- add/remove 😕 reaction
    },
    review_diff = {
      add_review_comment = "<space>ca",    -- add a new review comment
      add_review_suggestion = "<space>sa", -- add a new review suggestion
      focus_files = "<leader>e",           -- move focus to changed file panel
      toggle_files = "<leader>b",          -- hide/show changed files panel
      next_thread = "]t",                  -- move to next thread
      prev_thread = "[t",                  -- move to previous thread
      select_next_entry = "]q",            -- move to previous changed file
      select_prev_entry = "[q",            -- move to next changed file
      close_review_tab = "<C-c>",          -- close review tab
    },
    submit_win = {
      approve_review = "<C-a>",            -- approve review
      comment_review = "<C-m>",            -- comment review
      request_changes = "<C-r>",           -- request changes review
      close_review_tab = "<C-c>",          -- close review tab
    },
    file_panel = {
      next_entry = "j",                    -- move to next changed file
      prev_entry = "k",                    -- move to previous changed file
      select_entry = "<cr>",               -- show selected changed file diffs
      refresh_files = "R",                 -- refresh changed files panel
      focus_files = "<leader>e",           -- move focus to changed file panel
      toggle_files = "<leader>b",          -- hide/show changed files panel
      select_next_entry = "]q",            -- move to previous changed file
      select_prev_entry = "[q",            -- move to next changed file
      close_review_tab = "<C-c>",          -- close review tab
    }
  }
})
end}
```

## 🚀 Usage

Just edit the issue title, body or comments as a regular buffer and use `:w(rite)` to sync the issue with GitHub.

## 🤖 Commands

There is only an `Octo <object> <action> [arguments]` command: 
If no command is passed, the argument to `Octo` is treated as a URL from where an issue or pr repo and number are extracted

| Object | Action | Arguments|
|---|---|---|
| issue | close | Close the current issue|
| | reopen | Reopen the current issue|
| | create [repo]| Creates a new issue in the current or specified repo |
| | edit [repo] <number> | Edit issue `<number>` in current or specified repo |
| | list [repo] [key=value] (1) | List all issues satisfying given filter |
| | search | Live issue search |
| | reload | Reload issue. Same as doing `e!`|
| | browser | Open current issue in the browser |
| pr | list [repo] [key=value] (2)| List all PRs satisfying given filter |
| | search | Live issue search |
| | edit [repo] <number> | Edit PR `<number>` in current or specified repo|
| | reopen | Reopen the current PR|
| | close | Close the current PR|
| | checkout | Checkout PR|
| | commits | List all PR commits|
| | changes | Show all PR changes (diff hunks)|
| | diff | Show PR diff |
| | merge [commit\|rebase\|squash] [delete] | Merge current PR using the specified method|
| | ready| Mark a draft PR as ready for review |
| | checks | Show the status of all checks run on the PR |
| | reload | Reload PR. Same as doing `e!`|
| | browser | Open current PR in the browser|
| gist | list [repo] [key=value] | List user gists |
| comment | add | Add a new comment |
| | delete | Delete a comment |
| thread | resolve| Mark a review thread as resolved |
| | unresolve | Mark a review thread as unresolved |
| label | add | Add a label from available label menu |
| | remove | Remove a label |
| assignees| add | Assign a user |
| | remove | Unassign a user |
| reviewer | add | Assign a PR reviewer |
| reaction | `thumbs_up` \| `+1` | Add 👍 reaction|
| | `thumbs_down` \| `-1` | Add 👎 reaction|
| | `eyes` | Add 👀 reaction|
| | `laugh` | Add 😄 reaction|
| | `confused` | Add 😕 reaction|
| | `rocket` | Add 🚀 reaction|
| | `heart` | Add ❤️ reaction|
| | `hooray` \| `party` \| `tada` | Add 🎉 reaction|
| card | add | Assign issue/PR to a project new card |
| | remove | Delete project card |
| | move | Move project card to different project/column|
| review| start| Start a new review |
| | submit| Submit the review |
| | resume| Edit a pending review for current PR |
| | discard| Deletes a pending review for current PR if any |
| | comments| View pending review comments |

0. `[repo]`: If repo is not provided, it will be derived from `<cwd>/.git/config`.

1. In-menu mappings:
- `<CR>`: Edit Issue
- `<C-b>`: Opens issue in web browser
[Available filter keys](https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters)

2. In-menu mappings:
- `<CR>`: Edit PR
- `<C-b>`: Opens PR in web browser
[Available keys](https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters)

3. In-menu mappings:
- `<CR>`: Append Gist to buffer
- `<C-b>`: Opens Gist in web browser
[Available keys](https://cli.github.com/manual/gh_gist_list):  `repo`\|`public`\|`secret`

## 🔥 Examples

```
Octo https://github.com/pwntester/octo.nvim/issues/12
Octo issue create
Octo issue create pwntester/octo.nvim
Octo comment add
Octo reaction add hooray
Octo issue edit pwntester/octo.nvim 1
Octo issue edit 1
Octo issue list createdBy=pwntester
Octo issue list neovim/neovim labels=bug,help\ wanted states=OPEN
```

## 📋 PR review

- Open the PR (eg: `Octo pr list` or `Octo pr edit XXX`)
- Start a review with `Octo review start` or resume a pending review with `Octo review resume`
- Quickfix will be populated with the PR changed files 
- Change quickfix entries with `]q` and `[q` or by selecting an entry in the quickfix window
- Add comments with `<space>ca` or suggestions with `<space>sa` on single or multiple visual-selected lines
  - A new buffer will appear in the alternate diff window. Cursor will be positioned in the new buffer
  - When ready, save the buffer to commit changes to GitHub
  - Move back to the diff window and move the cursor, the thread buffer will hide
- Hold the cursor on a line with a comment to show a thread buffer with all the thread comments
  - To modify, delete, react or reply to a comment, move to the window containing the thread buffer
  - Perform any operations as if you were in a regular issue buffer 
- Review pending comments with `Octo review comments`
  - Use <CR> to jump to the selected pending comment
- When ready, submit the review with `Octo review submit`
- A new float window will pop up. Enter the top level review comment and exit to normal mode. Then press `<C-m>` to submit a comment, `<C-a>` to approve it or `<C-r>` to request changes

## 🍞 Completion
- Issue/PR id completion (#)
- User completion (@)

## 🎨 Colors
| Highlight Group             | Defaults to     |
| ---                         | ---             |
| *OctoDirty*                 | ErrorMsg        |
| *OctoIssueTitle*            | PreProc         |
| *OctoIssueId*               | Question        |
| *OctoEmpty*                 | Comment         |
| *OctoFloat*                 | NormalNC        |
| *OctoDate*                  | Comment         |
| *OctoSymbol*                | Comment         |
| *OctoTimelineItemHeading*   | Comment         |
| *OctoDetailsLabel*          | Title           |
| *OctoMissingDetails*        | Comment         |
| *OctoDetailsValue *         | Identifier      |
| *OctoDiffHunkPosition*      | NormalFloat     |
| *OctoCommentLine*           | TabLineSel      |
| *OctoEditable*              | NormalFloat     |
| *OctoViewer*                | GitHub color    |
| *OctoBubble*                | NormalFloat     |
| *OctoBubbleGreen*           | GitHub color    |
| *OctoBubbleRed*             | GitHub color    |
| *OctoUser*                  | OctoBubble      |
| *OctoUserViewer*            | OctoViewer      |
| *OctoReaction*              | OctoBubble      |
| *OctoReactionViewer*        | OctoViewer      |
| *OctoPassingTest*           | GitHub color    |
| *OctoFailingTest*           | GitHub color    |
| *OctoPullAdditions*         | GitHub color    |
| *OctoPullDeletions*         | GitHub color    |
| *OctoPullModifications*     | GitHub color    |
| *OctoStateOpen*             | GitHub color    |
| *OctoStateClosed*           | GitHub color    |
| *OctoStateMerge*            | GitHub color    |
| *OctoStatePending*          | GitHub color    |
| *OctoStateApproved*         | OctoStateOpen   |
| *OctoStateChangesRequested* | OctoStateClosed |
| *OctoStateCommented*        | Normal          |
| *OctoStateDismissed*        | OctoStateClosed |

The term `GitHub color` refers to the colors used in the WebUI.
The (addition) `viewer` means the user of the plugin or more precisely the user authenticated via the `gh` CLI tool used to retrieve the data from GitHub.

## 🙋 FAQ

**How can I disable bubbles for XYZ?**

Each text-object that makes use of a bubble (except labels) do use their own highlight group that linkes per default to the main bubble highlight group. To disable most bubbles at once you can simply link `OctoBubble` to `Normal`. To only disable them for a certain plain do the same for the specific sub-group (e.g. `OctoUser`).

**Why do my issue titles or markdown syntax do not get highlighted properly?**

The title, body and comments of an issue or PR are special as they get special highlighting applied and is an editable section. Due to the latter property it gets the `OctoEditable` highlighting via a special signs `linehl` setting. This takes precedence over the buffer internal highlights. To only get the background highlighted by the editable section, set `OctoEditable` to a highlight with a background color definition only.

## ✋ Contributing

Contributions are always welcome!

See [`CONTRIBUTING`](/CONTRIBUTING.md) for ways to get started.

Please adhere to this project's [`CODE_OF_CONDUCT`](/CODE_OF_CONDUCT).

## 📜 License

[MIT](https://choosealicense.com/licenses/mit/)
