#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/lua/octo/config.lua"
README_FILE="$REPO_ROOT/README.md"

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

BLOCK_FILE="$TMPDIR_LOCAL/config_block.txt"
TRANSFORMED_FILE="$TMPDIR_LOCAL/transformed.txt"

# Extract lines between -- BEGIN_CONFIG and -- END_CONFIG (exclusive)
awk '/-- BEGIN_CONFIG/{found=1; next} /-- END_CONFIG/{found=0} found' "$CONFIG_FILE" > "$BLOCK_FILE"

total_lines=$(wc -l < "$BLOCK_FILE" | tr -d '[:space:]')

# Transform:
#   first line:  "  return {" -> "require\"octo\".setup {"
#   last line:   "  }" -> "}"
#   other lines: strip 2 leading spaces
awk -v total="$total_lines" '
  NR == 1 { print "require\"octo\".setup {"; next }
  NR == total { print "}"; next }
  { if (substr($0, 1, 2) == "  ") print substr($0, 3); else print $0 }
' "$BLOCK_FILE" > "$TRANSFORMED_FILE"

# Replace content between <!-- BEGIN_CONFIG --> and <!-- END_CONFIG --> in README
{
  in_block=0
  while IFS= read -r line; do
    if [[ "$line" == "<!-- BEGIN_CONFIG -->" ]]; then
      echo "<!-- BEGIN_CONFIG -->"
      echo '```lua'
      cat "$TRANSFORMED_FILE"
      echo '```'
      echo "<!-- END_CONFIG -->"
      in_block=1
    elif [[ "$line" == "<!-- END_CONFIG -->" ]]; then
      in_block=0
    elif [[ "$in_block" == "0" ]]; then
      echo "$line"
    fi
  done < "$README_FILE"
} > "${README_FILE}.tmp" && mv "${README_FILE}.tmp" "$README_FILE"

echo "README.md config section updated from lua/octo/config.lua"
