# octo.nvim
Plugin to work with GitHub issues and PRs from Neovim. Just edit the issue description/comments and save it with `:w`.
Modified description or comments are highlighted in the signcolumn.


![](https://i.imgur.com/pv9MSJW.png)


## Installation

Use your favourite plugin manager to install it. eg:

```
Plug 'pwntester/octo.nvim'
```

## Requirements

- Install [GitHub CLI](https://cli.github.com/)
- Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for using the `ListXXX` commands which enables to fuzzy pick issues from a dropdown menu.

```
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
```


## Commands

- `Issue [repo] <id>`: Opens specified issue.
- `NewIssue [repo]`: Create new issue in specific repo.
- `CloseIssue`: Close current issue.
- `ReopenIssue`: Reopen current issue.
- `NewComment`: Add new comment to current issue.

- `AddLabel <label>`
- `RemoveLabel <label>`
- `AddAssignee <assignee>`
- `RemoveAssignee <assignee>`
- `AddReviewer <reviewer>`
- `RemoveReviewer <reviewer>`

- `ListIssues [repo] [key=value]*`: Fuzzy pick Issues.
  - Available [options](https://cli.github.com/manual/gh_issue_list):
    - `author`
    - `assignee`
    - `mention`
    - `label`
    - `milestone`
    - `state`
    - `limit`
  - Mappings:
    - `<CR>`: Edit issue 
    - `<C-t>`: Opens issue in web browser
- `ListPRs [repo] [key=value]*`: Fuzzy pick Pull Requests.
  - Available [options](https://cli.github.com/manual/gh_pr_list):
    - `assignee`
    - `label`
    - `state`
    - `base`
    - `limit`
  - Mappings:
    - `<CR>`: Edit PR
    - `<C-t>`: Opens PR in web browser
    - `<C-o>`: Checkout PR
- `ListGists [repo] [key=value]*`: Fuzzy pick Gists.
  - Available [options](https://cli.github.com/manual/gh_gist_list):
    - `repo`
    - `public`
    - `secret`
  - Mappings:
    - `<CR>`: Append Gist to buffer
    - `<C-t>`: Opens Gist in web browser

* If repo is not provided, it will be derived from CWD.

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

| Name | Default |
------------------
|`OctoNvimDirty`|`ErrorMsg` |
|`OctoNvimCommentHeading`|`PreProc`|
|`OctoNvimCommentUser`|`Underlined`|
|`OctoNvimIssueTitle`|`PreProc`|
|`OctoNvimIssueId`|`Question`|
|`OctoNvimIssueOpen`|`MoreMsg`|
|`OctoNvimIssueClosed`|`ErrorMsg`|
|`OctoNvimEmpty`|`Comment`|
|`OctoNvimFloat`|`NormalNC`|

## TODO

- [ ] autocompletion for @person

## Credits
All `List` commands are taken from @windwp [Telescope extension](https://github.com/nvim-telescope/telescope-github.nvim) and adapted to edit issues.
