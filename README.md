# OCTO.NVIM

![](https://i.imgur.com/JWkHXSa.png)
![](https://i.imgur.com/UuYyncG.png)

## Disclaimer

This is a WIP plugin, I take no responsibility of the use of this plugin.

## Installation

Use your favourite Plugin manager

## Requirements

Set an env. variable named `GITHUB_PAT` containing your GitHub username and Personal Access Token:
e.g. `pwntester:3123123ab4324bf12371231321feb`

## Commands

- `Issue <id> [<repo>]`: Opens an issue specified by Id. If repo is not provided, it will be derived from CWD.
- `NewIssue <repo>`: Create new issue in specific repo. If repo is not provided, it will be derived from CWD.
- `CloseIssue`: Close issue.
- `ReopenIssue`: Reopen issue.
- `NewComment`: Add new comment to open issue.

## Usage

Use `w(rite)` to save issue (title/description/comments).

## Highlight groups

- OctoNvimDirty: ErrorMsg 
- OctoNvimCommentHeading: PreProc
- OctoNvimCommentUser: Underlined

- OctoNvimIssueTitle: PreProc
- OctoNvimIssueId: Question
- OctoNvimIssueOpen: MoreMsg
- OctoNvimIssueClosed: ErrorMsg

- OctoNvimEmpty: Comment

- OctoNvimFloat: NormalNC

## TODO

- navigate links to other issues
- autocompletion on #issues, @person
- support pagination
- command to hide details float
