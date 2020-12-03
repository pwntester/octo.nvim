# octo.nvim
Plugin to work with GitHub issues and PRs from Neovim. Just edit the issue description/comments and save it with `:w`.
Modified description or comments are highlighted in the signcolumn.


![](https://i.imgur.com/ZRhBvls.png)


## Installation

Use your favourite Plugin manager to install it.

```
Plug 'pwntester/octo.nvim'
```

## Requirements

Set an environment variable named `OCTO_GITHUB_TOKEN` containing your GitHub username and Personal Access Token. e.g. `pwntester:3123123ab4324bf12371231321feb`

Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for using the `ListXXX` commands which enables to fuzzy pick issues from a dropdown menu.

```
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
```


## Commands

- `Issue [<repo>] <id>`: Opens an issue specified by Id. If repo is not provided, it will be derived from CWD.
- `NewIssue <repo>`: Create new issue in specific repo. If repo is not provided, it will be derived from CWD.
- `CloseIssue`: Close issue.
- `ReopenIssue`: Reopen issue.
- `NewComment`: Add new comment to open issue.
- `ListIssues <opts: key=value>`: (require [GitHub CLI](https://cli.github.com) to be installed). Fuzzy pick Issues.
- `ListGists<opts: key=value>`: (require [GitHub CLI](https://cli.github.com) to be installed). Fuzzy pick Gists.
- `ListPRs<opts: key=value>`: (require [GitHub CLI](https://cli.github.com) to be installed). Fuzzy pick Pull Requests.
- `AddLabel`
- `RemoveLabel`
- `AddAssignee`
- `RemoveAssignee`

## Usage

Just edit the issue title, description or comments as a regular buffer and use `:w(rite)` to sync the issue with GitHub.

## Completion

`<C-x><C-o>`: When cursor is located at text that matches `#\d*` will popup a list of repo issues starting with the same id prefix.

## Mappings

`<Plug>(GoToIssue)` can be used to navigate to a local repo issue. By default mapped to `gi` but can be overriden with: 

```
nmap gi <Plug>(GoToIssue)
```

## Highlight groups

  - `OctoNvimDirty`: `ErrorMsg` 
  - `OctoNvimCommentHeading`: `PreProc`
  - `OctoNvimCommentUser`: `Underlined`
  - `OctoNvimIssueTitle`: `PreProc`
  - `OctoNvimIssueId`: `Question`
  - `OctoNvimIssueOpen`: `MoreMsg`
  - `OctoNvimIssueClosed`: `ErrorMsg`
  - `OctoNvimEmpty`: `Comment`
  - `OctoNvimFloat`: `NormalNC`

## TODO

  - [x] navigate links to other issues
  - [x] autocompletion for #issues
  - [x] command to add labels
  - [x] command to add assignees
  - [ ] autocompletion for @person
  - [ ] support pagination
