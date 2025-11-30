# Contributing to Octo.Nvim

Welcome to Octo! This document is a guideline about how to contribute to Octo.
If you find something incorrect or missing, please leave comments / suggestions.

## Before you get started

### Code of Conduct

Please make sure to read and observe our [Code of Conduct](./CODE_OF_CONDUCT.md).

### Setting up your development environment

Please install [`neovim`](https://neovim.io/) and [`GitHub CLI`](https://cli.github.com/) in your system.

## Contributing

We are always very happy to have contributions, whether for typo fix, bug fix,
or big new features. Please do not ever hesitate to ask a question or send a
Pull Request.

Please check if there are any existing Issues or Pull Requests that relate to
your contribution.

### Open an Issue / PR

We use [GitHub Issues](https://github.com/pwntester/octo.nvim/issues) and [Pull Requests](https://github.com/pwntester/octo.nvim/pulls) for trackers.

If you find a typo in document, find a bug in code, or want new features, or
want to give suggestions, you can [open an Issue on
GitHub](https://github.com/pwntester/octo.nvim/issues/new) to report it. Please
follow the guideline message in the Issue template.

If you want to contribute, please follow the [contribution
workflow](#github-workflow) and create a new Pull Request. If your PR contains
large changes, e.g. component refactor or new components, please write detailed
documents about its design and usage.

Note that a single PR should not be too large. If heavy changes are required,
it's better to separate the changes to a few individual PRs. Raise in either
Issues or Discussions before making large changes.

### GitHub workflow

We use the `master` branch as the development branch, which indicates that this
is an unstable branch.

Here are the workflow for contributors:

1. Fork the repository: `gh repo fork pwntester/octo.nvim`
1. Create a new branch and work on it
1. Keep your branch in sync
1. Commit your changes (make sure your commit message concise)
1. Push your commits to your forked repository
1. Create a Pull Request: `gh pr create`

Please follow [the Pull Request template](./.github/PULL_REQUEST_TEMPLATE.md).
Please make sure the PR has a corresponding Issue.

After creating a PR, one or more reviewers will be assigned to the pull
request. The reviewers will review the code.


### Code review

All code should be well reviewed by one or more committers. Some principles:

- Readability: Important code should be well-documented. Comply with our code style.
- Elegance: New functions, classes or components should be well designed.
- CI/CD checks: All tests and checks should pass before merging.
