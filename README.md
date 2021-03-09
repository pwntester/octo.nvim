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
| | reload | |
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
| | reload | |
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
| reaction | add | <+1\|-1\|eyes\|laugh\|confused\|rocket\|hooray>|
| | delete | <+1\|-1\|eyes\|laugh\|confused\|rocket\|hooray>|
| card | add | |
| | delete | |
| | move | |
| review| start| Start a new review |
| | submit| Submit the review |
| | resume| Edit a pending review for current PR |
| | discard| Deletes a pending review for current PR if any |
| | comments| View pending review comments |
| | threads | View all review threads (comment+replies)|

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
- Quickfix will be populated with the changed files 
- Change quickfix entries with `]q` and `[q` or by selecting an entry in the quickfix window
- Add comments with `<space>ca` or `:OctoAddReviewComment` on single or multiple lines
- Add suggestions with `<space>sa` or `:OctoAddReviewSuggestion` on single or multiple lines
- Edit comments/suggestions with `<space>ce`
- A new split will open. Enter the comment and save it (`:w`). Optionally close the split

![](https://i.imgur.com/l9z4tpg.png)

- Add as many comments as needed
- Review comments with `Octo review comments`
  - Use <CR> to jump to the selected comment
  - Use <c-e> to edit the selected comment
  - Use <c-d> to delete the selected comment

![](https://i.imgur.com/2DKPZq9.png)

- When ready submit the review with `Octo review submit`
- A new float window will pop up. Enter the top level review comment and exit to normal mode. Then press `<C-m>` to submit a comment, `<C-a>` to approve it or `<C-r>` to request changes

![](https://i.imgur.com/aRHqIhg.png)

## Viewing PR Reviews

![](https://camo.githubusercontent.com/97aaf7efe7c8ff45cbc4359f28339fd9f9dd7ba3609fbd14b0649a979af15431/68747470733a2f2f692e696d6775722e636f6d2f71495a5a6b48342e706e67) 

- Open the PR (eg: `Octo pr list` or `Octo pr edit XXX`)
- Open review threads view with `Octo review threads`
- Quickfix will be populated with the changed files 
- Change quickfix entries with `]q` and `[q` or by selecting an entry in the quickfix window
- Jump between comments with `]c` and `[c`
- You can reply to a comment, delete them, add/remove reactions, etc. as if you where in an Octo issue buffer

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
| `<space>va` | request reViewer                      |
| `<space>vd` | delete reViewer                       |
| `<space>rh` | add :heart: reaction                  |
| `<space>rp` | add :hooray: reaction                 |
| `<space>re` | add :eyes: reaction                   |
| `<space>rl` | add :laugh: reaction                  |
| `<space>rc` | add :confused: reaction               |
| `<space>r+` | add :+1: reaction                     |
| `<space>r-` | add :-1: reaction                     |
| `<space>rr` | add :rocket: reaction                 |
| `<C-o>`     | open issue/pull in browser            |
| `<C-r>`     | reload current issue/pull             |


## Highlight groups
| Name                         | Default          |
| ---                          | ---              |
| `OctoNvimDirty`              | `ErrorMsg`       |
| `OctoNvimIssueTitle`         | `PreProc`        |
| `OctoNvimIssueId`            | `Question`       |
| `OctoNvimIssueOpen`          | `MoreMsg`        |
| `OctoNvimIssueClosed`        | `ErrorMsg`       |
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

## FAQ

**How can I disable bubbles for XYZ?**

Each text-object that makes use of a bubble (except labels) do use their own highlight group that linkes per default to the main bubble highlight group. To disable most bubbles at once you can simply link `OctoNvimBubble` to `Normal`. To only disable them for a certain plain do the same for the specific sub-group (e.g. `OctoNvimUser`).

**Why do my issue titles or markdown syntax do not get highlighted properly?**

The title, body and comments of an issue or PR are special as they get special highlighting applied and is an editable section. Due to the latter property it gets the `OctoNvimEditable` highlighting via a special signs `linehl` setting. This takes precedence over the buffer internal highlights. To only get the background highlighted by the editable section, set `OctoNvimEditable` to a highlight with a background color definition only.
