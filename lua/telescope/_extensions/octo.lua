local menu = require'octo.menu'
return require'telescope'.register_extension {
  exports = {
    commits = menu.commits,
    gists = menu.gists,
    issues = menu.issues,
    prs = menu.pull_requests,
  },
}
