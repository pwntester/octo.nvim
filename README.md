# OCTO.NVIM

![](https://i.imgur.com/JWkHXSa.png)
![](https://i.imgur.com/UuYyncG.png)

## Disclaimer

This is a WIP plugin, I take no responsibility of the use of this plugin.

## Installation

Use your favourite Plugin manager to install it.

## Requirements

Set an env. variable named `GITHUB_PAT` containing your GitHub username and Personal Access Token:
e.g. `pwntester:3123123ab4324bf12371231321feb`

## Commands

- `Issue [<repo>] <id>`: Opens an issue specified by Id. If repo is not provided, it will be derived from CWD.
- `NewIssue <repo>`: Create new issue in specific repo. If repo is not provided, it will be derived from CWD.
- `CloseIssue`: Close issue.
- `ReopenIssue`: Reopen issue.
- `NewComment`: Add new comment to open issue.

## Usage

Just edit the issue title, description or comments as a regular buffer and use `w(rite)` to sync the issue with GitHub.

## Completion

`<C-x><C-o>`: When located after `#\d*` is will popup a list of repo issues starting with the same prefix.

## Mappings

`<Plug>(GoToIssue)` can be used to navigate to a local repo issue. By default mapped to `gi` but can be overriden with: 

```
nmap gi <Plug>(GoToIssue)
```

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

## Fuzzy pickers

By default, this plugin does not expose any command to list and fuzzy pick a repo issue. However, it exposes source/sink functions to be used with your fuzzy picker of choice. For example, it can be integrated with [Telescope.nvim](https://github.com/nvim-lua/telescope.nvim) with the following function:

```
local function issues(opts, repo)

  local results = {}
  local resp = require'octo'.get_repo_issues(repo, {})
  for _,i in ipairs(resp.issues) do
    table.insert(results, {
      number = i.number;
      title = i.title;
    })
  end

  local make_issue_entry = function(result)
    return {
      valid = true;
      entry_type = make_entry.types.GENERIC;
      value = tostring(result.number);
      ordinal = tostring(result.number);
      display = string.format('#%d - %s', result.number, result.title);
    }
  end

  local custom_mappings = function(prompt_bufnr, map)
    local run_command = function()
      local selection = actions.get_selected_entry(prompt_bufnr)
      actions.close(prompt_bufnr)
      local cmd = string.format([[ lua require'octo'.get_issue('%s', '%s') ]], selection.value, repo)
      vim.cmd [[stopinsert]]
      vim.cmd(cmd)
    end
    map('i', '<CR>', run_command)
    map('n', '<CR>', run_command)
    return true
  end

  pickers.new(opts, {
    prompt = 'Issues';
    finder = finders.new_table({
      results = results;
      entry_maker = make_issue_entry;
    });
    sorter = sorters.get_generic_fuzzy_sorter();
    attach_mappings = custom_mappings;
  }):find()
end
```

## TODO

  - [x] navigate links to other issues
  - [x] autocompletion for #issues
  - [ ] autocompletion for @person
  - [ ] support pagination
  - [ ] command to hide details float
