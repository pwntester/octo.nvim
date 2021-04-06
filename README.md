# octo.nvim
Plugin to work with GitHub issues and PRs from Neovim. Just edit the issue description/comments and save it with `:w`.
Modified description or comments are highlighted in the signcolumn.

### Issue
![](https://i.imgur.com/ipbMFUs.png)

### Pull Request (checks)
![](https://i.imgur.com/xfE6yN2.png)

## Installation

Use your favourite plugin manager to install it. eg:

```
Plug 'pwntester/octo.nvim'
```

## Requirements

- Install [GitHub CLI](https://cli.github.com/)
- Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

```
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'

-- To use Telescope interface for octo pickers 
lua require('telescope').load_extension('octo')
```

## Commands

There is only an `Octo <object> <action> [arguments]` command: 

| Object | Action | Arguments|
|---|---|---|
| issue | close | |
| | reopen | |
| | create | [repo] |
| | edit | [repo] <number> |
| | list | [repo] [key=value]*<br>[Available keys](https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters)<br>Mappings:<br>`<CR>`: Edit issue<br>`<C-b>`: Opens issue in web browser |
| | search | |
| | reload | same as doing `e!`|
| | browser | |
| pr | list | [repo] [key=value]<br>[Available keys](https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters)<br>Mappings:<br>`<CR>`: Edit PR<br>`<C-b>`: Opens PR in web browser<br>`<C-o>`: Checkout PR |
| | search | |
| | edit | [repo] <number> |
| | open | |
| | close | |
| | checkout | |
| | commits | |
| | changes | |
| | diff | |
| | merge | [commit\|rebase\|squash] [delete] |
| | ready| |
| | checks | |
| | reload | same as doing `e!`|
| | browser | |
| gist | list | [repo] [key=value]*<br>[Available keys](https://cli.github.com/manual/gh_gist_list):  `repo`\|`public`\|`secret`<br>Mappings:<br>`<CR>`: Append Gist to buffer<br>`<C-b>`: Opens Gist in web browser |
| comment | add | |
| | delete | |
| thread | resolve| Mark a review thread as resolved |
| | unresolve | Mark a review thread as unresolved |
| label | add | <label> |
| | delete | <label> |
| assignees| add | <assignee> |
| | delete | <assignee> |
| reviewer | add | <reviewer> |
| | delete | <reviewer> |
| reaction | thumbs_up \| +1 | |
| | thumbs_down \| -1 | |
| | eyes | |
| | laugh | |
| | confused | |
| | rocket | |
| | hooray \| party \| tada | |
| card | add | |
| | delete | |
| | move | |
| review| start| Start a new review |
| | submit| Submit the review |
| | resume| Edit a pending review for current PR |
| | discard| Deletes a pending review for current PR if any |
| | comments| View pending review comments |

* If repo is not provided, it will be derived from `<cwd>/.git/config`.

If no command is passed, the argument to `Octo` is treated as a URL from where an issue or pr repo and number are extracted

Examples:

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

## Usage
Just edit the issue title, description or comments as a regular buffer and use `:w(rite)` to sync the issue with GitHub.

## PR review
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

## Completion
- Issue/PR id completion (#)
- User completion (@)

## Mappings
`<Plug>(OctoOpenIssueAtCursor)`: Open issue/pr at cursor with Octo


## In-issue mappings
| Mapping     | Description                           |
| ---         | ---                                   |
| `<space>gi` | navigate to a local repo issue        |
| `<space>ca` | add comment                           |
| `<space>cd` | delete comment                        |
| `<space>ic` | close issue                           |
| `<space>io` | reopen issue                          |
| `<space>il` | list open issues on same repo         |
| `<space>po` | checkout pull request                 |
| `<space>pc` | list pull request commits             |
| `<space>pf` | list pull request files               |
| `<space>pd` | show pull request diff                |
| `<space>pr` | mark pull request as ready for review |
| `<space>pm` | merge pull request                    |
| `<space>la` | add label                             |
| `<space>ld` | delete label                          |
| `<space>aa` | add assignee                          |
| `<space>ad` | delete assignee                       |
| `<space>va` | request reviewer                      |
| `<space>vd` | delete reviewer                       |
| `<space>rh` | add/remove :heart: reaction           |
| `<space>rp` | add/remove :hooray: reaction          |
| `<space>re` | add/remove :eyes: reaction            |
| `<space>rl` | add/remove :laugh: reaction           |
| `<space>rc` | add/remove :confused: reaction        |
| `<space>r+` | add/remove :+1: reaction              |
| `<space>r-` | add/remove :-1: reaction              |
| `<space>rr` | add/remove :rocket: reaction          |
| `<C-o>`     | open issue/pull in browser            |
| `<C-r>`     | reload current issue/pull             |
| `[c`        | go to previous comment                |
| `]c`        | go to next comment                    |


## Highlight groups
| Name                         | Default          |
| ---                          | ---              |
| `OctoNvimDirty`              | `ErrorMsg`       |
| `OctoNvimIssueTitle`         | `PreProc`        |
| `OctoNvimIssueId`            | `Question`       |
| `OctoNvimEmpty`              | `Comment`        |
| `OctoNvimFloat`              | `NormalNC`       |
| `OctoNvimDate`               | `Comment`        |
| `OctoNvimSymbol`             | `Comment`        |
| `OctoNvimTimelineItemHeading`| `Comment`        |
| `OctoNvimDetailsLabel`       | `Title`          |
| `OctoNvimMissingDetails`     | `Comment`        |
| `OctoNvimDetailsValue `      | `Identifier`     |
| `OctoNvimDiffHunkPosition`   | `NormalFloat`    |
| `OctoNvimCommentLine`        | `TabLineSel`     |
| `OctoNvimEditable`           | `NormalFloat`    |
| `OctoNvimViewer`             | GitHub color     |
| `OctoNvimBubble`             | `NormalFloat`    |
| `OctoNvimBubbleGreen`        | GitHub color     |
| `OctoNvimBubbleRed`          | GitHub color     |
| `OctoNvimUser`               | `OctoNvimBubble` |
| `OctoNvimUserViewer`         | `OctoNvimViewer` |
| `OctoNvimReaction`           | `OctoNvimBubble` |
| `OctoNvimReactionViewer`     | `OctoNvimViewer` |
| `OctoNvimPassingTest`        | GitHub color     |
| `OctoNvimFailingTest`        | GitHub color     |
| `OctoNvimPullAdditions`      | GitHub color     |
| `OctoNvimPullDeletions`      | GitHub color     |
| `OctoNvimPullModifications`  | GitHub color     |
| `OctoNvimStateOpen`          | GitHub color     |
| `OctoNvimStateClosed`        | GitHub color     |
| `OctoNvimStateMerge`         | GitHub color     |
| `OctoNvimStatePending`       | GitHub color     |
| `OctoNvimStateApproved`      | `OctoNvimStateOpen` |
| `OctoNvimStateChangesRequested` | `OctoNvimStateClosed` |
| `OctoNvimStateCommented`     | `Normal` |
| `OctoNvimStateDismissed`     | `OctoNvimStateClosed` |

The term `GitHub color` refers to the colors used in the WebUI.
The (addition) `viewer` means the user of the plugin or more precisely the user authenticated via the `gh` CLI tool used to retrieve the data from GitHub.

## Settings

- `g:octo_date_format`: Date format (default: "%Y %b %d %I:%M %p %Z")
- `g:octo_remote_order`: Order to resolve the remote for the current working directory (default: ["upstream", "origin"])
- `g:octo_qf_height`: Percent (when 0 < value < 1) or absolute (when value > 1) height of quickfix window (defaults to 20% relative)
- `g:octo_bubble_delimiter_left`: Left (unicode) character to draw a bubble for labels etc. (default: "")
- `g:octo_bubble_delimiter_right`: Right (unicode) character to draw a bubble for labels etc. (default: "")
- `g:octo_icon_user`: Icon used to signal user names (default: "")
- `g:octo_icon_reaction_viewer_hint`: Icon as alternative or to complement the highlighting of reactions by the viewer himself (default: "")
- `g:octo_snippet_context_lines`: Number of additional lines displayed from the diff-hunk for single-line comments (default: 3)
- `g:octo_github_hostname`: Host name to use for non-public GHE (GitHub Enterprise) instances (default: null).

## FAQ

**How can I disable bubbles for XYZ?**

Each text-object that makes use of a bubble (except labels) do use their own highlight group that linkes per default to the main bubble highlight group. To disable most bubbles at once you can simply link `OctoNvimBubble` to `Normal`. To only disable them for a certain plain do the same for the specific sub-group (e.g. `OctoNvimUser`).

**Why do my issue titles or markdown syntax do not get highlighted properly?**

The title, body and comments of an issue or PR are special as they get special highlighting applied and is an editable section. Due to the latter property it gets the `OctoNvimEditable` highlighting via a special signs `linehl` setting. This takes precedence over the buffer internal highlights. To only get the background highlighted by the editable section, set `OctoNvimEditable` to a highlight with a background color definition only.

## Contributing

Contributions are always welcomed! Please refer to [CONTRIBUTING](/CONTRIBUTING) for detailed guidelines.
You can start with the issues labeled with `good first issue`.
