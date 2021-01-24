# octo.nvim
Plugin to work with GitHub issues and PRs from Neovim. Just edit the issue description/comments and save it with `:w`.
Modified description or comments are highlighted in the signcolumn.

### Issue
![](https://i.imgur.com/ipbMFUs.png)

### Pull Request (checks)
![](https://i.imgur.com/xfE6yN2.png)

### Pull Request (review threads)
![](https://camo.githubusercontent.com/97aaf7efe7c8ff45cbc4359f28339fd9f9dd7ba3609fbd14b0649a979af15431/68747470733a2f2f692e696d6775722e636f6d2f71495a5a6b48342e706e67) 

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
| | open | |
| | create | [repo] |
| | edit | [repo] <number> |
| | list | [repo] [key=value]*<br>[Available keys](https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters)<br>Mappings:<br>`<CR>`: Edit issue<br>`<C-b>`: Opens issue in web browser |
| | search | |
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

Examples:

```
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

## Completion

- Issue/PR id completion (#)
- User completion (@)

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

| Name                     | Default      |
| ---                      | ---          |
| `OctoNvimDirty`          | `ErrorMsg`   |
| `OctoNvimCommentHeading` | `PreProc`    |
| `OctoNvimCommentUser`    | `Underlined` |
| `OctoNvimIssueTitle`     | `PreProc`    |
| `OctoNvimIssueId`        | `Question`   |
| `OctoNvimIssueOpen`      | `MoreMsg`    |
| `OctoNvimIssueClosed`    | `ErrorMsg`   |
| `OctoNvimEmpty`          | `Comment`    |
| `OctoNvimFloat`          | `NormalNC`   |
| `OctoNvimBubbleRed`      | `DiffDelete` |
| `OctoNvimBubbleGreen`    | `DiffAdd`    |
| `OctoNvimBubbleDelimiter`| `NormalFloat`|
| `OctoNvimBubbleBody`     | `NormalFloat`|
| `OctoNvimDetailsLabel`   | `Title`      |
| `OctoNvimMissingDetails` | `Comment`    |
| `OctoNvimDetailsValue `  | `Identifier` |

## Settings

`g:octo_date_format`: Date format (default: "%Y %b %d %I:%M %p %Z")
`g:octo_remote_order`: Order to resolve the remote for the current working directory (default: ["upstream", "origin"])
`g:octo_qf_height`: Height of quickfix window
