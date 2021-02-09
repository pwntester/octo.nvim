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
| | files | |
| | diff | |
| | merge | [commit\|rebase\|squash] [delete] |
| | ready| |
| | checks | |
| | reviews | |
| | reload | |
| | browser | |
| gist | list | [repo] [key=value]*<br>[Available keys](https://cli.github.com/manual/gh_gist_list):  `repo`\|`public`\|`secret`<br>Mappings:<br>`<CR>`: Append Gist to buffer<br>`<C-b>`: Opens Gist in web browser |
| comment | add | |
| | delete | |
| | resolve | |
| | unresolve | |
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
- Change to the directory containing the repo/PR
- Open the PR (eg: `Octo pr list` or `Octo pr edit XXX`)
- If not already in the PR branch, checkout the PR with `Octo pr checkout`
- Start a review with `Octo review start`
- Add comments with `:OctoReviewComment` on single or multiple lines
- A new split will open. Enter the comment and save it (`:w`). Optionally close the split

![](https://i.imgur.com/l9z4tpg.png)

- Add as many comments as needed
- Review comments with `Octo review comments`

![](https://i.imgur.com/2DKPZq9.png)

- When ready submit the review with `Octo review submit`
- A new float window will pop up. Enter the top level review comment and exit to normal mode. Then press `<C-m>` to submit a comment, `<C-a>` to approve it or `<C-r>` to request changes

![](https://i.imgur.com/aRHqIhg.png)

## Viewing PR Reviews

![](https://camo.githubusercontent.com/97aaf7efe7c8ff45cbc4359f28339fd9f9dd7ba3609fbd14b0649a979af15431/68747470733a2f2f692e696d6775722e636f6d2f71495a5a6b48342e706e67) 

- Change to the directory containing the repo/PR
- Open the PR (eg: `Octo pr list` or `Octo pr edit XXX`)
- If not already in the PR branch, checkout the PR with `Octo pr checkout`
- Open review threads view with `Octo pr reviews`
- Quickfix will be populated with changed files 
- Change quickfix entries with `]q` and `[q` or by selecting an entry in the quickfix window
- Jump between comments with `]c` and `[c`
- You can reply to a comment, delete them, add/remove reactions, etc. as if you where in an Octo issue buffer

## Completion
- Issue/PR id completion (#)
- User completion (@)


## Mappings
`<Plug>(OctoOpenURLAtCursor)`: Open URL at cursor with Octo


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

## Highlight groups
| Name                        | Default          |
| ---                         | ---              |
| `OctoNvimDirty`             | `ErrorMsg`       |
| `OctoNvimCommentHeading`    | `PreProc`        |
| `OctoNvimCommentUser`       | `Underlined`     |
| `OctoNvimIssueTitle`        | `PreProc`        |
| `OctoNvimIssueId`           | `Question`       |
| `OctoNvimIssueOpen`         | `MoreMsg`        |
| `OctoNvimIssueClosed`       | `ErrorMsg`       |
| `OctoNvimEmpty`             | `Comment`        |
| `OctoNvimFloat`             | `NormalNC`       |
| `OctoNvimBubbleRed`         | `DiffDelete`.fg  |
| `OctoNvimBubbleGreen`       | `DiffAdd`.fg     |
| `OctoNvimBubbleDelimiter`   | `NormalFloat`.bg |
| `OctoNvimBubbleBody`        | `NormalFloat`.bg |
| `OctoNvimDetailsLabel`      | `Title`          |
| `OctoNvimMissingDetails`    | `Comment`        |
| `OctoNvimDetailsValue `     | `Identifier`     |
| `OctoNvimDiffHunkPosition`  | `NormalFloat`.bg |
| `OctoNvimCommentLine`       | `TabLineSel`     |
| `OctoNvimPassingTest`       | `DiffAdd`        |
| `OctoNvimFailingTest`       | `DiffDelete`     |
| `OctoNvimPullAdditions`     | `DiffAdd`        |
| `OctoNvimPullDeletions`     | `DiffDelete`     |
| `OctoNvimPullModifications` | `DiffChange`     |

## Settings

- `g:octo_date_format`: Date format (default: "%Y %b %d %I:%M %p %Z")
- `g:octo_remote_order`: Order to resolve the remote for the current working directory (default: ["upstream", "origin"])
- `g:octo_qf_height`: Absolute height of quickfix window (defaults to 20% relative)
