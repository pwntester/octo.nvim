# octo.nvim
Plugin to work with GitHub issues and PRs from Neovim. Just edit the issue description/comments and save it with `:w`.
Modified description or comments are highlighted in the signcolumn.

### Issue
![](https://i.imgur.com/ipbMFUs.png)

### Pull Request
![](https://i.imgur.com/rN4tSPP.png)

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
```


## Commands

There is only an `Octo <object> <action> [arguments]` command: 

| Object | Action | Arguments|
|---|---|---|
| issue | close | |
| | open | |
| | create | [repo] |
| | edit | [repo] <number> |
| | list | [repo] [key=value]*<br>[Available keys](https://cli.github.com/manual/gh_issue_list): `author`\|`assignee`\|`mention`\|`label`\|`milestone`\|`state`\|`limit`<br>Mappings:<br>`<CR>`: Edit issue<br>`<C-t>`: Opens issue in web browser |
| pr | list | [repo] [key=value]*<br>[Available keys](https://cli.github.com/manual/gh_pr_list):  `assignee`\|`label`\|`state`\|`base`\|`limit`<br>Mappings:<br>`<CR>`: Edit PR<br>`<C-t>`: Opens PR in web browser<br>`<C-o>`: Checkout PR |
| | edit | [repo] <number> |
| | checkout | |
| | commits | |
| | files | |
| | diff | |
| | merge | [commit\|rebase\|squash] [delete] |
| | ready| |
| | checks | |
| | reviews | |
| gist | list | [repo] [key=value]*<br>[Available keys](https://cli.github.com/manual/gh_gist_list):  `repo`\|`public`\|`secret`<br>Mappings:<br>`<CR>`: Append Gist to buffer<br>`<C-t>`: Opens Gist in web browser |
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

* If repo is not provided, it will be derived from `<cwd>/.git/config`.

Examples:

```
Octo issue create
Octo issue create pwntester/octo.nvim
Octo comment add
Octo reaction add hooray
Octo issue edit pwntester/octo.nvim 1
Octo issue edit 1
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


## Credits
All `List` commands are taken from @windwp [Telescope extension](https://github.com/nvim-telescope/telescope-github.nvim) and adapted to edit issues.
