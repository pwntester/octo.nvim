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

![issues](https://user-images.githubusercontent.com/125701/124568675-76130600-de45-11eb-9944-2607c5863f37.gif)

![prs](https://user-images.githubusercontent.com/125701/124568138-e8cfb180-de44-11eb-994a-0791d8be63ad.gif)


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
* [📋 PR reviews](#-pr-reviews)
* [🍞 Completion](#-completion)
* [🎨 Colors](#-colors)
* [🏷️  Status Column](#-statuscolumn)
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
- Install [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- Install [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)

## 📦 Installation

Use your favourite plugin manager to install it. eg:

```lua
use {
  'pwntester/octo.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  config = function ()
    require"octo".setup()
  end
}
```

## ⚙️ Configuration

```lua
require"octo".setup({
  use_local_fs = false,                    -- use local files on right side of reviews
  enable_builtin = false,                  -- shows a list of builtin actions when no action is provided
  default_remote = {"upstream", "origin"}; -- order to try remotes
  ssh_aliases = {},                        -- SSH aliases. e.g. `ssh_aliases = {["github.com-work"] = "github.com"}`
  reaction_viewer_hint_icon = "";         -- marker for user reactions
  user_icon = " ";                        -- user icon
  timeline_marker = "";                   -- timeline marker
  timeline_indent = "2";                   -- timeline indentation
  right_bubble_delimiter = "";            -- bubble delimiter
  left_bubble_delimiter = "";             -- bubble delimiter
  github_hostname = "";                    -- GitHub Enterprise host
  snippet_context_lines = 4;               -- number or lines around commented lines
  gh_env = {},                             -- extra environment variables to pass on to GitHub CLI, can be a table or function returning a table
  timeout = 5000,                          -- timeout for requests between the remote server
  ui = {
    use_signcolumn = true,                 -- show "modified" marks on the sign column
  },
  issues = {
    order_by = {                           -- criteria to sort results of `Octo issue list`
      field = "CREATED_AT",                -- either COMMENTS, CREATED_AT or UPDATED_AT (https://docs.github.com/en/graphql/reference/enums#issueorderfield)
      direction = "DESC"                   -- either DESC or ASC (https://docs.github.com/en/graphql/reference/enums#orderdirection)
    }
  },
  pull_requests = {
    order_by = {                           -- criteria to sort the results of `Octo pr list`
      field = "CREATED_AT",                -- either COMMENTS, CREATED_AT or UPDATED_AT (https://docs.github.com/en/graphql/reference/enums#issueorderfield)
      direction = "DESC"                   -- either DESC or ASC (https://docs.github.com/en/graphql/reference/enums#orderdirection)
    },
    always_select_remote_on_create = "false" -- always give prompt to select base remote repo when creating PRs
  },
  file_panel = {
    size = 10,                             -- changed files panel rows
    use_icons = true                       -- use web-devicons in file panel (if false, nvim-web-devicons does not need to be installed)
  },
  mappings = {
    issue = {
      close_issue = { lhs = "<space>ic", desc = "close issue" },
      reopen_issue = { lhs = "<space>io", desc = "reopen issue" },
      list_issues = { lhs = "<space>il", desc = "list open issues on same repo" },
      reload = { lhs = "<C-r>", desc = "reload issue" },
      open_in_browser = { lhs = "<C-b>", desc = "open issue in browser" },
      copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
      add_assignee = { lhs = "<space>aa", desc = "add assignee" },
      remove_assignee = { lhs = "<space>ad", desc = "remove assignee" },
      create_label = { lhs = "<space>lc", desc = "create label" },
      add_label = { lhs = "<space>la", desc = "add label" },
      remove_label = { lhs = "<space>ld", desc = "remove label" },
      goto_issue = { lhs = "<space>gi", desc = "navigate to a local repo issue" },
      add_comment = { lhs = "<space>ca", desc = "add comment" },
      delete_comment = { lhs = "<space>cd", desc = "delete comment" },
      next_comment = { lhs = "]c", desc = "go to next comment" },
      prev_comment = { lhs = "[c", desc = "go to previous comment" },
      react_hooray = { lhs = "<space>rp", desc = "add/remove 🎉 reaction" },
      react_heart = { lhs = "<space>rh", desc = "add/remove ❤️ reaction" },
      react_eyes = { lhs = "<space>re", desc = "add/remove 👀 reaction" },
      react_thumbs_up = { lhs = "<space>r+", desc = "add/remove 👍 reaction" },
      react_thumbs_down = { lhs = "<space>r-", desc = "add/remove 👎 reaction" },
      react_rocket = { lhs = "<space>rr", desc = "add/remove 🚀 reaction" },
      react_laugh = { lhs = "<space>rl", desc = "add/remove 😄 reaction" },
      react_confused = { lhs = "<space>rc", desc = "add/remove 😕 reaction" },
    },
    pull_request = {
      checkout_pr = { lhs = "<space>po", desc = "checkout PR" },
      merge_pr = { lhs = "<space>pm", desc = "merge commit PR" },
      squash_and_merge_pr = { lhs = "<space>psm", desc = "squash and merge PR" },
      list_commits = { lhs = "<space>pc", desc = "list PR commits" },
      list_changed_files = { lhs = "<space>pf", desc = "list PR changed files" },
      show_pr_diff = { lhs = "<space>pd", desc = "show PR diff" },
      add_reviewer = { lhs = "<space>va", desc = "add reviewer" },
      remove_reviewer = { lhs = "<space>vd", desc = "remove reviewer request" },
      close_issue = { lhs = "<space>ic", desc = "close PR" },
      reopen_issue = { lhs = "<space>io", desc = "reopen PR" },
      list_issues = { lhs = "<space>il", desc = "list open issues on same repo" },
      reload = { lhs = "<C-r>", desc = "reload PR" },
      open_in_browser = { lhs = "<C-b>", desc = "open PR in browser" },
      copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
      goto_file = { lhs = "gf", desc = "go to file" },
      add_assignee = { lhs = "<space>aa", desc = "add assignee" },
      remove_assignee = { lhs = "<space>ad", desc = "remove assignee" },
      create_label = { lhs = "<space>lc", desc = "create label" },
      add_label = { lhs = "<space>la", desc = "add label" },
      remove_label = { lhs = "<space>ld", desc = "remove label" },
      goto_issue = { lhs = "<space>gi", desc = "navigate to a local repo issue" },
      add_comment = { lhs = "<space>ca", desc = "add comment" },
      delete_comment = { lhs = "<space>cd", desc = "delete comment" },
      next_comment = { lhs = "]c", desc = "go to next comment" },
      prev_comment = { lhs = "[c", desc = "go to previous comment" },
      react_hooray = { lhs = "<space>rp", desc = "add/remove 🎉 reaction" },
      react_heart = { lhs = "<space>rh", desc = "add/remove ❤️ reaction" },
      react_eyes = { lhs = "<space>re", desc = "add/remove 👀 reaction" },
      react_thumbs_up = { lhs = "<space>r+", desc = "add/remove 👍 reaction" },
      react_thumbs_down = { lhs = "<space>r-", desc = "add/remove 👎 reaction" },
      react_rocket = { lhs = "<space>rr", desc = "add/remove 🚀 reaction" },
      react_laugh = { lhs = "<space>rl", desc = "add/remove 😄 reaction" },
      react_confused = { lhs = "<space>rc", desc = "add/remove 😕 reaction" },
    },
    review_thread = {
      goto_issue = { lhs = "<space>gi", desc = "navigate to a local repo issue" },
      add_comment = { lhs = "<space>ca", desc = "add comment" },
      add_suggestion = { lhs = "<space>sa", desc = "add suggestion" },
      delete_comment = { lhs = "<space>cd", desc = "delete comment" },
      next_comment = { lhs = "]c", desc = "go to next comment" },
      prev_comment = { lhs = "[c", desc = "go to previous comment" },
      select_next_entry = { lhs = "]q", desc = "move to previous changed file" },
      select_prev_entry = { lhs = "[q", desc = "move to next changed file" },
      close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
      react_hooray = { lhs = "<space>rp", desc = "add/remove 🎉 reaction" },
      react_heart = { lhs = "<space>rh", desc = "add/remove ❤️ reaction" },
      react_eyes = { lhs = "<space>re", desc = "add/remove 👀 reaction" },
      react_thumbs_up = { lhs = "<space>r+", desc = "add/remove 👍 reaction" },
      react_thumbs_down = { lhs = "<space>r-", desc = "add/remove 👎 reaction" },
      react_rocket = { lhs = "<space>rr", desc = "add/remove 🚀 reaction" },
      react_laugh = { lhs = "<space>rl", desc = "add/remove 😄 reaction" },
      react_confused = { lhs = "<space>rc", desc = "add/remove 😕 reaction" },
    },
    submit_win = {
      approve_review = { lhs = "<C-a>", desc = "approve review" },
      comment_review = { lhs = "<C-m>", desc = "comment review" },
      request_changes = { lhs = "<C-r>", desc = "request changes review" },
      close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
    },
    review_diff = {
      add_review_comment = { lhs = "<space>ca", desc = "add a new review comment" },
      add_review_suggestion = { lhs = "<space>sa", desc = "add a new review suggestion" },
      focus_files = { lhs = "<leader>e", desc = "move focus to changed file panel" },
      toggle_files = { lhs = "<leader>b", desc = "hide/show changed files panel" },
      next_thread = { lhs = "]t", desc = "move to next thread" },
      prev_thread = { lhs = "[t", desc = "move to previous thread" },
      select_next_entry = { lhs = "]q", desc = "move to previous changed file" },
      select_prev_entry = { lhs = "[q", desc = "move to next changed file" },
      close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
      toggle_viewed = { lhs = "<leader><space>", desc = "toggle viewer viewed state" },
      goto_file = { lhs = "gf", desc = "go to file" },
    },
    file_panel = {
      next_entry = { lhs = "j", desc = "move to next changed file" },
      prev_entry = { lhs = "k", desc = "move to previous changed file" },
      select_entry = { lhs = "<cr>", desc = "show selected changed file diffs" },
      refresh_files = { lhs = "R", desc = "refresh changed files panel" },
      focus_files = { lhs = "<leader>e", desc = "move focus to changed file panel" },
      toggle_files = { lhs = "<leader>b", desc = "hide/show changed files panel" },
      select_next_entry = { lhs = "]q", desc = "move to previous changed file" },
      select_prev_entry = { lhs = "[q", desc = "move to next changed file" },
      close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
      toggle_viewed = { lhs = "<leader><space>", desc = "toggle viewer viewed state" },
    }
  }
})
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
| | url | Copies the URL of the current issue to the system clipboard|
| pr | list [repo] [key=value] (2)| List all PRs satisfying given filter |
| | search | Live issue search |
| | edit [repo] <number> | Edit PR `<number>` in current or specified repo|
| | reopen | Reopen the current PR|
| | create | Creates a new PR for the current branch|
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
| | url | Copies the URL of the current PR to the system clipboard|
| repo | list (3) | List repos user owns, contributes or belong to |
| | fork | Fork repo |
| | browser | Open current repo in the browser|
| | url | Copies the URL of the current repo to the system clipboard|
| | view | Open a repo by path ({organization}/{name})|
| gist | list [repo] [key=value] (4) | List user gists |
| comment | add | Add a new comment |
| | delete | Delete a comment |
| thread | resolve| Mark a review thread as resolved |
| | unresolve | Mark a review thread as unresolved |
| label | add [label] | Add a label from available label menu |
| | remove [label] | Remove a label |
| | create [label] | Create a new label |
| assignee| add [login] | Assign a user |
| | remove [login] | Unassign a user |
| reviewer | add [login] | Assign a PR reviewer |
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
| | commit | Pick a specific commit to review |
| | close | Close the review window and return to the PR |
| actions |  | Lists all available Octo actions|
| search | <query> | Search GitHub for issues and PRs matching the [query](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests) |

0. `[repo]`: If repo is not provided, it will be derived from `<cwd>/.git/config`.

1. In-menu mappings:
- `<CR>`: Edit Issue
- `<C-b>`: Opens issue in the browser
- `<C-y>`: Copies URL to system clipboard

[Available filter keys](https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters)
- since
- createdBy
- assignee
- mentioned
- labels
- milestone
- states


2. In-menu mappings:
- `<CR>`: Edit PR
- `<C-b>`: Opens PR in the browser
- `<C-o>`: Checkout PR
- `<C-y>`: Copies URL to system clipboard

[Available filter keys](https://github.com/pwntester/octo.nvim/blob/master/lua/octo/pickers/telescope/provider.lua#L34)
- baseRefName
- headRefName
- labels
- states

3. In-menu mappings:
- `<CR>`: View repo
- `<C-b>`: Opens repo in the browser
- `<C-y>`: Copies URL to system clipboard

4. In-menu mappings:
- `<CR>`: Append Gist to buffer
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
Octo search assignee:pwntester is:pr
```

## 📋 PR reviews

- Open the PR (eg: `Octo <PR url>` or `Octo pr list` or `Octo pr edit <PR number>`)
- Start a review with `Octo review start` or resume a pending review with `Octo review resume`
- A new tab will show a panel with changed files and two windows showing the diff on any of them.
- Change panel entries with `]q` and `[q` or by selecting an entry in the window
- Add comments with `<space>ca` or suggestions with `<space>sa` on single or multiple visual-selected lines
  - A new buffer will appear in the alternate diff window. The cursor will be positioned in the new buffer
  - When ready, save the buffer to commit changes to GitHub
  - Move back to the diff window and move the cursor, the thread buffer will hide
- Hold the cursor on a line with a comment to show a thread buffer with all the thread comments
  - To modify, delete, react or reply to a comment, move to the window containing the thread buffer
  - Perform any operations as if you were in a regular issue buffer
- Review pending comments with `Octo review comments`
  - Use <CR> to jump to the selected pending comment
- If you want to review a specific commit, use `Octo review commit` to pick a commit. The file panel will get filtered to show only files changed by that commit. Any comments placed on these files will be applied at that specific commit level and will be added to the pending review.
- When ready, submit the review with `Octo review submit`
- A new float window will pop up. Enter the top level review comment and exit to normal mode. Then press `<C-m>` to submit a comment, `<C-a>` to approve it or `<C-r>` to request changes

## 🍞 Completion
Octo provides a built-in omnifunc completion for issues, PRs and users that you can trigger using `<C-x><C-o>`. Alternately, if you use [`nvim-cmp`](https://github.com/hrsh7th/nvim-cmp) for completion, you can use the [`cmp-git`](https://github.com/petertriho/cmp-git/) source to provide issues, PRs, commits and users completion.

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
| *OctoDetailsValue*          | Identifier      |
| *OctoDiffHunkPosition*      | NormalFloat     |
| *OctoCommentLine*           | TabLineSel      |
| *OctoEditable*              | NormalFloat bg  |
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

## 🏷️  Status Column
If you are using the `vim.opt.statuscolumn` feature, you can disable Octo's comment marks in the `signcolumn` and replace them with any customizations on the `statuscolumn`.

Disable the `signcolumn` with:

```lua
ui = {
    use_signcolumn = false
}
```

Then, provide a `statuscolumn` replacement such as:

```lua
local function mk_hl(group, sym)
  return table.concat({ "%#", group, "#", sym, "%*" })
end

_G.get_statuscol_octo = function(bufnum, lnum)
  if vim.api.nvim_buf_get_option(bufnum, "filetype") == "octo" then
    if type(octo_buffers) == "table" then
      local buffer = octo_buffers[bufnum]
      if buffer then
        buffer:update_metadata()
        local hl = "OctoSignColumn"
        local metadatas = {buffer.titleMetadata, buffer.bodyMetadata}
        for _, comment_metadata in ipairs(buffer.commentsMetadata) do
          table.insert(metadatas, comment_metadata)
        end
        for _, metadata in ipairs(metadatas) do
          if metadata and metadata.startLine and metadata.endLine then
            if metadata.dirty then
              hl = "OctoDirty"
            else
              hl = "OctoSignColumn"
            end
            if lnum - 1 == metadata.startLine and lnum - 1 == metadata.endLine then
              return mk_hl(hl, "[ ")
            elseif lnum - 1 == metadata.startLine then
              return mk_hl(hl, "┌ ")
            elseif lnum - 1 == metadata.endLine then
              return mk_hl(hl, "└ ")
            elseif metadata.startLine < lnum - 1 and lnum - 1 < metadata.endLine then
              return mk_hl(hl, "│ ")
            end
          end
        end
      end
    end
  end
  return "  "
end

vim.opt.statuscolumn = "%{%v:lua.get_statuscol_octo(bufnr(), v:lnum)%}"
```

## 🙋 FAQ

**How can I disable bubbles for XYZ?**

Each text-object that makes use of a bubble (except labels) do use their own highlight group that linkes per default to the main bubble highlight group. To disable most bubbles at once you can simply link `OctoBubble` to `Normal`. To only disable them for a certain plain do the same for the specific sub-group (e.g. `OctoUser`).

**Why do my issue titles or markdown syntax do not get highlighted properly?**

The title, body and comments of an issue or PR are special as they get special highlighting applied and is an editable section. Due to the latter property it gets the `OctoEditable` highlighting via a special signs `linehl` setting. This takes precedence over the buffer internal highlights. To only get the background highlighted by the editable section, set `OctoEditable` to a highlight with a background color definition only.

**Why am I getting authentication error from gh?**

This means that are either using a GITHUB_TOKEN to authenticate or `gh` is not authenticated.

In case of the former, run:

```
GITHUB_TOKEN= gh auth login
```

... and choose a method to authorise access for `gh`.

`gh` must store the creds so it can work in a subshell.

**Can I use treesitter markdown parser with octo buffers?**

Just add the following lines to your TreeSitter config:

```lua
vim.treesitter.language.register('markdown', 'octo')
```

**How can I filter PRs by filter keys that aren't available?**

You can use the search command `:Octo search [query]`.
The [search syntax](https://docs.github.com/en/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax)
and available search terms are available in [GitHub documentation](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-author).

For example to search for PRs with author you can use this command:

```
:Octo search is:pr author:pwntester repo:github/codeql
```

Note: You need to provide the `repo`, otherwise it will search for every PR by that user.

**How to enable autocompletion for issues/prs (`#`) and users (`@`)?**

Add the following mappings for `octo` file type:
- `vim.keymap.set("i", "@", "@<C-x><C-o>", { silent = true, buffer = true })`
- `vim.keymap.set("i", "#", "#<C-x><C-o>", { silent = true, buffer = true })`

## ✋ Contributing

Contributions are always welcome!

See [`CONTRIBUTING`](/CONTRIBUTING.md) for ways to get started.

Please adhere to this project's [`CODE_OF_CONDUCT`](/CODE_OF_CONDUCT.md).

## 🌟 Credits
The PR review panel is heavily inspired in [diffview.nvim](https://github.com/sindrets/diffview.nvim)

## 📜 License

[MIT](https://choosealicense.com/licenses/mit/)
