# Octo.nvim

Edit and review GitHub issues and pull requests from the comfort of your favorite editor.


    
## Screenshots

![](https://i.imgur.com/ipbMFUs.png)

![](https://i.imgur.com/xfE6yN2.png)

## Features

- Edit GitHub issues and PRs
- Add/Modify/Delete comments
- Add/Remove label, reactions, assignees, project cards, reviewers, etc.
- Add Review PRs

## Installation 

Use your favourite plugin manager to install it. eg:

```
use {'pwntester/octo.nvim'}
```

## Requirements

- Install [GitHub CLI](https://cli.github.com/)
- Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
 
## Usage

Just edit the issue title, body or comments as a regular buffer and use `:w(rite)` to sync the issue with GitHub.

## Commands

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
| | open | |
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
| | delete | Remove a label |
| assignees| add | Assign a user |
| | delete | Unassign a user |
| reviewer | add | Assign a PR reviewer |
| | delete | Unassign a PR reviewer |
| reaction | `thumbs_up` \| `+1` | Add :+1: reaction|
| | `thumbs_down` \| `-1` | Add :-1: reaction|
| | `eyes` | Add :eyes: reaction|
| | `laugh` | Add :laugh: reaction|
| | `confused` | Add :confused: reaction|
| | `rocket` | Add :rocket: reaction|
| | `hooray` \| `party` \| `tada` | Add :hooray: reaction|
| card | add | Assign issue/PR to a project new card |
| | delete | Delete project card |
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

## Examples

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

### Issue/PR/Thread mappings
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

### Thread review mappings
| `[c`        | go to previous change |
| `]c`        | go to next change |
| `[q`        | go to previous file |
| `]q`        | go to next file |
| `[t`        | go to previous thread |
| `]t`        | go to next thread|
| `<C-c>`   | close review tab|


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

Contributions are always welcome!

See `contributing.md` for ways to get started.

Please adhere to this project's `code of conduct`.

## License

[MIT](https://choosealicense.com/licenses/mit/)
