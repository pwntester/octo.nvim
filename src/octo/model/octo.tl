-- Declares the different kinds of the input data to operate with.
global type OctoKind = enum
  "issue"
  "pull"
  "repo"

  -- TODO: Refactor to remove duplicates
  "pull_request"
end

-- Holds the supported repository host providers.
global type RepoHostType = enum
  "github"
  "gitlab"
end
