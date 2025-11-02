#!/bin/bash
set -euo pipefail

# Find all tracked files that contain "vim.notify"
matches=$(git grep -n "vim.notify" -- "lua/octo/" || true)

if [ -z "$matches" ]; then
  echo "❌ No occurrences of 'vim.notify' found in the repo. There should be one in the lua/octo/notify module."
  exit 1
fi

count=$(echo "$matches" | wc -l | tr -d '[:space:]')

if [ "$count" -eq 1 ]; then
  echo "✅ Exactly one 'vim.notify' found:"
  echo "$matches"
  exit 0
else
  echo "❌ Found $count occurrences of 'vim.notify':"
  echo "$matches" | sed 's/^/   /'
  echo
  echo "Use utils.info or utils.error instead of vim.notify directly."
  exit 1
fi
